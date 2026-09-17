import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'safety_foreground_service.dart';

part 'safety_watch.g.dart';

/// The foreground service for the platform actually being run on.
///
/// Lives here rather than beside the glove, because the service is no longer
/// the glove's: a journey needs it too, and whichever consumer happened to own
/// the provider would look like the only one that mattered.
@Riverpod(keepAlive: true)
SafetyForegroundService safetyForegroundService(Ref ref) =>
    createForegroundService();

/// Owns the foreground service's lifetime, as the union of everything that
/// currently needs it.
///
/// ## The bug this exists to remove
///
/// The service used to be started by one consumer — a connected glove — and
/// nothing else. A Safe Journey armed with no glove paired therefore ran with
/// no foreground service at all, so Android froze the process the moment the
/// screen went off: the speech recogniser stopped, the camera policy timer
/// stopped, the once-a-second post of the fused score stopped. Meanwhile
/// `threatPipelineArmed` watches only the journey, so the app went on saying
/// it was armed. A woman wearing the glasses and no glove, phone in her
/// pocket, had no audio detection and nothing on screen to tell her.
///
/// ## Why a set of reasons rather than a counter or a flag
///
/// A flag cannot answer "may I stop it now": a journey ending while the glove
/// is still connected would take the glove's BLE stream down with it, which is
/// the same class of failure in the opposite direction. A counter would answer
/// that, but could not say *what* the service is for — and the Android service
/// types and the notification text both have to name the real work. So the
/// reasons are kept, and both are derived from them.
///
/// Claims are idempotent: two callers claiming [WatchReason.glove] is not a
/// thing that happens, but a re-entrant listener firing twice is, and it must
/// not turn into two starts or a release that undercounts.
@Riverpod(keepAlive: true)
class SafetyWatch extends _$SafetyWatch {
  /// Resolved once and held. The teardown below has to stop the service, and
  /// `ref.read` throws once disposal has begun — so the only moment this can
  /// be obtained is before there is any need for it.
  late final SafetyForegroundService _service;

  final _reasons = <WatchReason>{};

  /// Whether the service is genuinely running, as reported by the platform.
  ///
  /// Not "whether we asked for it". A denied notification permission or an OEM
  /// that kills background work means it is not running, and the UI has to be
  /// able to say the phone-in-pocket case does not work on this device rather
  /// than claim it does because the request was made.
  @override
  bool build() {
    _service = ref.read(safetyForegroundServiceProvider);
    ref.onDispose(() {
      // Nothing is watching once this is gone; leaving the notification up
      // would outlive the thing it describes.
      _reasons.clear();
      _service.stop();
    });
    return false;
  }

  /// What the service is currently being kept alive for.
  Set<WatchReason> get reasons => Set.unmodifiable(_reasons);

  /// Declares that [reason]'s work has started.
  Future<void> claim(WatchReason reason) async {
    if (!_reasons.add(reason)) return;
    // Re-declared even when already running: the new reason may need a service
    // type the running service did not ask for, and a journey starting under
    // an existing glove watch is exactly that case.
    state = await _service.start(reasons: Set.of(_reasons));
  }

  /// Declares that [reason]'s work has finished.
  ///
  /// Stops the service only when nothing else needs it.
  Future<void> release(WatchReason reason) async {
    if (!_reasons.remove(reason)) return;
    if (_reasons.isEmpty) {
      await _service.stop();
      state = false;
      return;
    }
    // Still needed, by fewer things. Re-declared so the departing reason's
    // service type is given up rather than held over something that has
    // stopped — a microphone type outliving the listening is a permission the
    // user's notification shade would keep reporting falsely.
    state = await _service.start(reasons: Set.of(_reasons));
  }
}
