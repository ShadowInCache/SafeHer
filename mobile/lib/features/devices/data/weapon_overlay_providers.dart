import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/weapon_overlay.dart';
import 'glasses_preview_providers.dart';
import 'ultralytics_weapon_detector.dart';
import 'weapon_detection_service.dart';

/// The detector that is currently feeding fusion, or null when none is.
///
/// Published by `ThreatPipeline` for exactly the reason
/// [activeGlassesVideoStreamProvider] is: so that anything else wanting the
/// detector's output joins it rather than starting a second one. Two YOLO
/// instances on one phone would halve the frame rate of the one that matters
/// and double the battery cost, to draw a rectangle that was already available.
///
/// **Read-only for the UI.** Nothing outside the pipeline may call `watch`,
/// `dispose` or `onStreamLost` on the service behind this provider — those
/// belong to whoever owns the alarm path.
final activeWeaponDetectionServiceProvider =
    StateProvider<WeaponDetectionService?>((ref) => null);

/// Whether this platform can run the detector on the phone at all.
///
/// The same condition `ThreatPipeline` applies, repeated rather than shared
/// because the two must not drift: the preview must never quietly start a
/// detector on a platform where the pipeline decided one cannot run.
bool get canRunWeaponDetectorOnDevice =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// The detector whose boxes the preview draws.
///
/// Resolves the same way [glassesPreviewSourceProvider] resolves its video:
/// borrow the pipeline's if a journey is running, otherwise own one.
///
/// ## Why the preview may start its own
///
/// The preview exists so a user can confirm the camera points where she thinks
/// it does, and so the system can be shown working without starting a Safe
/// Journey. A preview that drew boxes only during an armed journey would be
/// useless for the second purpose — and asking someone to trigger a real
/// emergency flow in order to see that detection works is a bad trade.
///
/// The detector this creates is **not wired to fusion**. Its `scores` stream
/// has no listener, so nothing it sees can reach `ThreatSignals.weapon`, raise
/// a threat level or dispatch an alert. It feeds a rectangle and nothing else.
/// That separation is the whole reason this is a different provider rather
/// than a flag on the pipeline's.
final weaponOverlayDetectorProvider =
    Provider.autoDispose<WeaponDetectionService?>((ref) {
  final active = ref.watch(activeWeaponDetectionServiceProvider);
  if (active != null) {
    // Borrowed. Deliberately not disposed here: it belongs to the pipeline,
    // and disposing it would disable weapon detection for the journey.
    return active;
  }

  if (!canRunWeaponDetectorOnDevice) return null;

  final source = ref.watch(glassesPreviewSourceProvider);
  // `isShared` means the pipeline owns the video, which can only happen when a
  // journey is armed -- and then `active` above is non-null and we never get
  // here. Checking anyway: if that invariant ever breaks, the wrong branch
  // would attach a second detector to the detector's own stream.
  if (source == null || source.isShared) return null;

  final service = WeaponDetectionService(
    detector: UltralyticsWeaponDetector(),
    // The same rate the pipeline uses on Android. Lower would make the box
    // visibly lag the video; higher would heat the phone to no visible gain,
    // since the stream itself only delivers 10-15 fps.
    inferenceInterval: const Duration(milliseconds: 200),
  );
  unawaited(service.prepareDetector());
  service.watch(source.stream.frames);
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

/// What the overlay should draw, kept current as inferences arrive.
///
/// Emits a [WeaponOverlayState] rather than raw frames so the filtering —
/// weapon classes only, above the draw threshold, with a usable box — happens
/// in one place that is unit-testable, instead of inside a painter.
///
/// Staleness is **not** handled here. The state carries the time of its last
/// inference and the widget asks `visibleAt(now)` when it builds, which it
/// does on every video frame. A ticker to expire boxes would be a second clock
/// racing the first for no benefit: if frames have stopped arriving there is
/// no video under the box to protect, and the preview has already replaced the
/// picture with a "lost the camera" message.
final weaponOverlayStateProvider =
    StreamProvider.autoDispose<WeaponOverlayState>((ref) {
  final service = ref.watch(weaponOverlayDetectorProvider);
  if (service == null) return const Stream<WeaponOverlayState>.empty();

  final controller = StreamController<WeaponOverlayState>();
  var state = const WeaponOverlayState();

  final subscription = service.overlayFrames.listen(
    (frame) {
      state = state.withFrame(
        frame.detections,
        at: frame.at,
        frameSize: frame.frameSize,
      );
      if (!controller.isClosed) controller.add(state);
    },
    onError: (Object error) {
      // A failure to produce boxes is not a reason to tear the overlay down,
      // and it must never surface as an error on the video. Clear and carry on.
      state = state.cleared();
      if (!controller.isClosed) controller.add(state);
    },
  );

  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(controller.close());
  });
  return controller.stream;
});
