import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/background/safety_foreground_service.dart';
import '../../../core/background/safety_watch.dart';
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

/// Claims the background watch for exactly as long as a glove is being
/// listened to.
///
/// Tied to the glove rather than to a switch of its own, because there is
/// nothing here for the service to keep alive when no glove is connected. A
/// persistent "watching your glove" notification sitting over no glove would
/// be the same lie this file exists to remove, in the opposite direction.
///
/// **It no longer starts and stops the service directly.** [SafetyWatch] owns
/// that, because the glove is not the only thing that needs the process kept
/// alive — an armed journey needs it for the microphone — and two owners
/// calling `start` and `stop` on one operating-system object means whichever
/// finished first switched the other one off.
///
/// The published value is whether the background watch is genuinely running,
/// which is what the Profile screen turns into "you can put your phone in
/// your pocket". It is asked of the platform rather than remembered, so a
/// service the system quietly stopped is not reported as active.
@Riverpod(keepAlive: true)
class GloveWatchService extends _$GloveWatchService {
  /// Resolved once and held rather than read where it is used: `ref.read`
  /// throws once disposal has begun.
  late final SafetyWatch _watch;

  @override
  bool build() {
    _watch = ref.read(safetyWatchProvider.notifier);

    ref.listen<GloveLinkState>(gloveLinkProvider, (previous, next) {
      if (previous?.isListening == next.isListening) return;
      _sync(next.isListening);
    }, fireImmediately: true);

    // Deliberately no teardown here. [SafetyWatch] stops the service when it
    // is disposed, and releasing a reason into a notifier that may already be
    // disposed would throw on the way out.
    return false;
  }

  Future<void> _sync(bool shouldWatch) async {
    if (shouldWatch) {
      await _watch.claim(WatchReason.glove);
    } else {
      await _watch.release(WatchReason.glove);
    }
    state = ref.read(safetyWatchProvider);
  }
}
