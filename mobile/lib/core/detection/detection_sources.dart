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
/// error, and its mirror is worse: auto-SOS from the glove used to work only
/// while the app was in the foreground, and nothing told anyone that. A phone
/// in a pocket -- the exact case the feature exists for -- raised no alarm.
///
/// That gap is now closed by a foreground service, but only when the service
/// is actually running, which the platform can refuse. So the pocket sentence
/// is gated on [backgroundWatchActive] rather than on the feature existing:
/// shipping the capability and asserting it unconditionally would recreate the
/// same lie with better machinery behind it.
///
/// So this combines both sources and states both limits, because a setting
/// that looks like protection and is not is the failure mode this codebase
/// keeps having to fix.
class DetectionSources {
  const DetectionSources({
    required this.backend,
    required this.gloveListening,
    this.backgroundWatchActive = false,
    this.journeyDetectionActive = false,
  });

  /// The server's account of its own models.
  final DetectionStatus backend;

  /// Whether a glove is connected and its classification stream subscribed.
  final bool gloveListening;

  /// Whether the foreground service is genuinely running, so detection
  /// continues with the app off screen.
  ///
  /// Governs both the glove and the journey pipeline, because one service
  /// keeps the whole process alive and either can be the thing that needs it.
  ///
  /// Defaults to false, and is the platform's answer rather than the app's
  /// intention. Starting the service can fail — notification permission
  /// denied, an OEM that kills it — and "we asked for it" is not the same
  /// claim as "it is running". Only the second one earns the sentence that
  /// tells a woman she can put her phone in her pocket.
  final bool backgroundWatchActive;

  /// Whether the three-signal pipeline is currently running.
  ///
  /// It arms with a Safe Journey and stops when the journey ends, because the
  /// microphone and the camera are the two most intrusive things this app can
  /// touch and "while she told us she is travelling" is a boundary she set
  /// herself.
  ///
  /// This screen has to know, because without it the standing text says
  /// "SafeHer cannot detect a threat by itself" while the phrase classifier is
  /// actively scoring what it hears. Under-reporting protection is the
  /// friendlier of the two errors and still an error.
  final bool journeyDetectionActive;

  /// True if anything at all can raise an alarm unaided right now.
  bool get anyActive =>
      gloveListening || backend.autoSosActive || journeyDetectionActive;

  /// True when the only thing that can is the glove.
  ///
  /// Worth distinguishing because the glove carries a caveat the backend does
  /// not: off screen it detects only while the foreground service is running,
  /// which is what [backgroundWatchActive] reports.
  bool get gloveOnly => gloveListening && !backend.autoSosActive;

  String get headline {
    if (gloveListening) return 'Your glove is watching';
    if (journeyDetectionActive) return 'Detection is on for this journey';
    if (backend.autoSosActive) return 'Automatic detection is on';
    return 'Automatic detection is not active yet';
  }

  String get detail {
    if (gloveListening) {
      // Both halves of the truth in one breath: what it does, and when it
      // stops. Someone deciding whether to rely on this deserves the second
      // half as much as the first.
      if (backgroundWatchActive) {
        // The pocket case is named explicitly rather than left implied. It is
        // the question this sentence is actually answering, and the previous
        // version of this text answered it the other way — so anyone who read
        // that one needs to be told plainly that it changed.
        return 'Your glove detects movement on the device itself and can raise '
            'the alarm when it passes your threshold. It keeps watching with '
            'your screen off and your phone in your pocket, for as long as the '
            'SafeHer notification is showing. SOS, the shake gesture and your '
            'contacts always work.';
      }
      return 'Your glove detects movement on the device itself and can raise '
          'the alarm when it passes your threshold. It only does this while '
          'SafeHer is open — a phone in your pocket will not trigger it. SOS, '
          'the shake gesture and your contacts always work.';
    }
    if (journeyDetectionActive) {
      // Named precisely, because "listening" is a word that deserves care.
      // What runs is speech recognition on the device: the words are scored
      // and dropped, and only a number is sent. Saying so is the difference
      // between a feature she can consent to and one she discovers.
      //
      // The off-screen half is gated for the same reason the glove's is. The
      // journey pipeline used to have no foreground service of its own at all
      // — only a connected glove ever started one — so a journey armed with
      // no glove paired stopped listening the moment the screen went off,
      // while this text promised listening and the pipeline reported itself
      // armed. Both halves now depend on the platform confirming the service.
      if (backgroundWatchActive) {
        return 'While this journey is running, SafeHer listens for words that '
            'sound like trouble. Speech is recognised on your phone and '
            'discarded — only a score leaves the device. It keeps listening '
            'with your screen off, for as long as the SafeHer notification is '
            'showing, and stops when the journey ends.';
      }
      return 'While this journey is running, SafeHer listens for words that '
          'sound like trouble. Speech is recognised on your phone and '
          'discarded — only a score leaves the device. It only does this while '
          'SafeHer is open — with your screen off, listening stops. It stops '
          'when the journey ends.';
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
