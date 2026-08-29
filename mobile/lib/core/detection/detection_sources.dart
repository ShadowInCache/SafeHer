import 'detection_status.dart';

/// Everything that can currently raise an alarm without the user, and the
/// honest limits on each.
///
/// **Why this exists.** The Profile screen used to report detection using the
/// backend's answer alone -- `/alerts/models`, which describes server-side
/// models that are not trained. That was true when the server was the only
/// place inference could happen. It is not true now: the glove runs an
/// XGBoost model on the ESP32 and reaches the phone over BLE with no server
/// in the path, so the app was telling a woman "automatic detection is not
/// active yet" while a connected glove was actively able to raise her alarm.
///
/// Under-reporting is the friendlier of the two errors but it is still an
/// error, and its mirror is worse: auto-SOS from the glove only works while
/// the app is in the foreground, because the trigger navigates. Nothing told
/// anyone that. A phone in a pocket -- the exact case the feature exists for
/// -- raises no alarm.
///
/// So this combines both sources and states both limits, because a setting
/// that looks like protection and is not is the failure mode this codebase
/// keeps having to fix.
class DetectionSources {
  const DetectionSources({required this.backend, required this.gloveListening});

  /// The server's account of its own models.
  final DetectionStatus backend;

  /// Whether a glove is connected and its classification stream subscribed.
  final bool gloveListening;

  /// True if anything at all can raise an alarm unaided right now.
  bool get anyActive => gloveListening || backend.autoSosActive;

  /// True when the only thing that can is the glove.
  ///
  /// Worth distinguishing because the glove carries a limitation the backend
  /// does not: it stops when the app leaves the foreground.
  bool get gloveOnly => gloveListening && !backend.autoSosActive;

  String get headline {
    if (gloveListening) return 'Your glove is watching';
    if (backend.autoSosActive) return 'Automatic detection is on';
    return 'Automatic detection is not active yet';
  }

  String get detail {
    if (gloveListening) {
      // Both halves of the truth in one breath: what it does, and when it
      // stops. Someone deciding whether to rely on this deserves the second
      // half as much as the first.
      return 'Your glove detects movement on the device itself and can raise '
          'the alarm when it passes your threshold. It only does this while '
          'SafeHer is open — a phone in your pocket will not trigger it. SOS, '
          'the shake gesture and your contacts always work.';
    }
    if (backend.autoSosActive) {
      return 'SafeHer raises the alarm on its own when the threat score passes '
          'your threshold.';
    }
    return 'No glove is connected and your wearables are not sending readings, '
        'so SafeHer cannot detect a threat by itself. SOS, the shake gesture '
        'and your emergency contacts all work as normal.';
  }
}
