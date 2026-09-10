import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'microphone_arbiter.g.dart';

/// Who is allowed to hold the microphone.
///
/// The platform gives it to one caller at a time, and SafeHer has two that
/// want it: threat listening, which runs for the whole journey, and evidence
/// recording, which starts the moment an SOS countdown begins.
///
/// **Evidence wins, always.** A recording of an assault is the thing a court
/// sees; a threat score during the emergency is worth nothing next to it,
/// because by then the alarm has already been raised and the score has no
/// remaining decision to inform. Losing the recording to keep scoring would
/// be trading the irreplaceable for the redundant.
enum MicrophoneUse {
  /// Nobody holds it.
  idle,

  /// Continuous threat listening during an armed journey. Yields to [evidence].
  threatListening,

  /// Evidence capture during an emergency. Yields to nothing.
  evidence,
}

/// Tracks which use currently owns the microphone.
///
/// Deliberately advisory rather than enforcing: it does not wrap the platform
/// APIs, it tells the threat monitor when to get out of the way. Wrapping them
/// would mean routing an emergency recording through a lock, and a lock is one
/// more thing that can fail while someone is being attacked.
///
/// The failure this prevents is real and was live in the shipped code: the
/// emergency screen calls `_startRecording()` on entry while the audio monitor
/// is still listening, and on Android `SpeechRecognizer` and `record` contend
/// for the same hardware. Whichever lost, lost silently.
@Riverpod(keepAlive: true)
class MicrophoneArbiter extends _$MicrophoneArbiter {
  @override
  MicrophoneUse build() => MicrophoneUse.idle;

  /// Claims the microphone for evidence capture.
  ///
  /// Called before the recorder starts, so the threat monitor has released the
  /// device by the time the recorder asks the platform for it.
  void claimForEvidence() => state = MicrophoneUse.evidence;

  /// Evidence capture has finished; threat listening may resume.
  void releaseEvidence() {
    if (state == MicrophoneUse.evidence) state = MicrophoneUse.idle;
  }

  /// Threat listening has started. Refused while evidence holds the device.
  bool claimForThreatListening() {
    if (state == MicrophoneUse.evidence) return false;
    state = MicrophoneUse.threatListening;
    return true;
  }

  void releaseThreatListening() {
    if (state == MicrophoneUse.threatListening) state = MicrophoneUse.idle;
  }

  /// Whether continuous threat listening is allowed right now.
  bool get threatListeningAllowed => state != MicrophoneUse.evidence;
}
