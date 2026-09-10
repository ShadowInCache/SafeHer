import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/background/safety_foreground_service.dart';
import '../../../core/local/app_preferences.dart';
import '../../devices/data/glove_link_providers.dart';
import '../../devices/domain/glove_protocol.dart';
import '../../devices/domain/glove_threat_detector.dart';

part 'glove_auto_trigger.g.dart';

/// One decision that the glove's readings justify raising the alarm.
///
/// A value rather than a bare flag so every request is a distinct object:
/// listeners fire on identity, and two falls a minute apart must be two
/// alarms, not one flag that was already true.
class GloveAlarmRequest {
  const GloveAlarmRequest({required this.classification, required this.raisedAt});

  /// The reading that completed the vote — kept so the incident can say why
  /// it fired, the way automatic incidents already do.
  final GloveClassification classification;

  final DateTime raisedAt;

  @override
  String toString() => 'GloveAlarmRequest(${classification.label}, $raisedAt)';
}

/// The platform's foreground service, or a no-op where there isn't one.
@Riverpod(keepAlive: true)
SafetyForegroundService safetyForegroundService(Ref ref) =>
    createForegroundService();

/// Votes on the glove's classifications and publishes the decision to alarm.
///
/// **Why this is a provider and not a widget.**  This vote used to live in the
/// `build()` method of `SafetyTriggerListener`. That worked on screen and
/// nowhere else: Flutter stops pumping frames when the app is not visible, so
/// `build()` stopped being called, the classifications went nowhere, and a
/// pocketed phone — the case the glove exists for — raised nothing. A
/// foreground service alone would not have fixed it; the process would have
/// been alive with nothing reading the stream.
///
/// A `ref.listen` callback is driven by provider state, not by the frame
/// pipeline, so it runs whether or not anything is being drawn.
///
/// It publishes a request rather than dispatching, or even navigating:
/// deciding to alarm and deciding how to show the countdown are different
/// jobs, and only the second one needs a `BuildContext`.
@Riverpod(keepAlive: true)
class GloveAutoTrigger extends _$GloveAutoTrigger {
  /// Held on the notifier so its window and cooldown survive everything a
  /// widget's lifetime does not.
  final _detector = GloveThreatDetector();
  GloveClassification? _lastSeen;

  @override
  GloveAlarmRequest? build() {
    ref.listen<GloveLinkState>(gloveLinkProvider, (previous, next) {
      if (!next.isListening) {
        // A dropped link clears the vote: readings from before a dropout must
        // not combine with ones after it into a window that never happened.
        _detector.reset();
        _lastSeen = null;
        return;
      }
      _consider(next.classification);
    });

    return null;
  }

  void _consider(GloveClassification? classification) {
    if (classification == null) return;
    // Telemetry ticks rebuild the link state too. Counting the same `FALL`
    // twice because the battery percentage changed would halve the evidence
    // an alarm actually needs.
    if (identical(classification, _lastSeen)) return;
    _lastSeen = classification;

    // Read, not watched: watching would rebuild this notifier when the user
    // moved the threshold slider, discarding a half-finished vote at the
    // moment it matters. Read at decision time is both current and stable.
    final threshold = ref.read(appPreferencesProvider).threatThreshold;

    final fire = _detector.shouldTrigger(
      classification,
      threshold: threshold,
      now: DateTime.now(),
    );
    if (!fire) return;

    state = GloveAlarmRequest(
      classification: classification,
      raisedAt: DateTime.now(),
    );
  }

  /// Visible for tests: how much of the current window has been filled.
  int get pendingHits => _detector.pendingHits;
}

/// Runs the foreground service for exactly as long as a glove is being
/// listened to.
///
/// Tied to the glove rather than to a switch of its own, because the service
/// has one job — keep the BLE stream and the vote alive — and there is nothing
/// for it to keep alive when no glove is connected. A persistent "SafeHer is
/// watching your glove" notification sitting over no glove would be the same
/// lie this file exists to remove, in the opposite direction.
///
/// Whether it is actually running is asked of the platform and published here,
/// so the UI can distinguish "the glove is connected" from "the glove will
/// still be watching when the screen goes off". They are not the same promise.
@Riverpod(keepAlive: true)
class GloveWatchService extends _$GloveWatchService {
  /// Resolved once and held, rather than read where it is used.
  ///
  /// The teardown below has to stop the service, and `ref.read` throws once
  /// disposal has begun — so the only moment this can be obtained is before
  /// there is any need for it.
  late final SafetyForegroundService _service;

  @override
  bool build() {
    _service = ref.read(safetyForegroundServiceProvider);

    ref.listen<GloveLinkState>(gloveLinkProvider, (previous, next) {
      if (previous?.isListening == next.isListening) return;
      _sync(next.isListening);
    }, fireImmediately: true);

    ref.onDispose(() {
      // Nothing is watching once this is gone; leaving the notification up
      // would outlive the thing it describes.
      _service.stop();
    });

    return false;
  }

  Future<void> _sync(bool shouldWatch) async {
    final service = _service;
    if (shouldWatch) {
      // `start` reports whether the service is genuinely running: a denied
      // notification permission or an OEM restriction means it is not, and
      // the app must say the phone-in-pocket case still does not work rather
      // than assume the request succeeded.
      state = await service.start();
    } else {
      await service.stop();
      state = false;
    }
  }
}
