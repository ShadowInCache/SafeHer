import 'evidence_recorder.dart';

/// Captures video evidence during an emergency (SRS FR-EMG-06).
///
/// **Why this is separate from [EvidenceRecorder], and why it is optional.**
///
/// The product design puts the camera in the smart glasses, where it is
/// pointed at whatever the wearer is facing. Those glasses do not exist yet,
/// so the only camera available is the phone's — and a phone in a pocket or
/// a bag films the inside of a pocket or a bag. That was the reason audio
/// was built first and alone, and it has not stopped being true.
///
/// So video is captured *in addition to* audio, never instead of it, and a
/// camera that fails must never cost the user her audio recording or delay
/// her alert. Audio is the evidence that works regardless of where the phone
/// is; video is the evidence that is worth a great deal on the occasions the
/// lens happens to be pointed at something.
///
/// It also gives YOLOv8 (SRS §6.1) an input path. Until this existed, the
/// weapon-detection model had nowhere to read frames from even in principle.
///
/// Kept as its own interface rather than extra methods on [EvidenceRecorder]
/// so that an implementation of one is not forced to stub the other, and so
/// the audio path — the one that matters most — keeps its narrow contract.
abstract class VideoEvidenceRecorder {
  /// Whether this platform has a usable camera.
  Future<bool> isSupported();

  /// True when camera access has already been granted.
  ///
  /// Note this asks only about the camera. Audio permission is the audio
  /// recorder's business, and conflating them would let a denied camera
  /// look like a denied microphone.
  Future<bool> hasPermission();

  /// Prompts for camera access, returning whether it was granted.
  Future<bool> requestPermission();

  /// Begins recording. Throws [EvidenceRecorderException] if it cannot.
  Future<void> start();

  /// Stops and returns what was captured, deleting the local copy.
  ///
  /// Returns null when nothing was recorded. As with audio, the caller
  /// treats that as "no video", never as a failure worth blocking an alert
  /// over.
  Future<EvidenceRecording?> stop();

  /// Abandons an in-progress recording without returning it.
  Future<void> cancel();

  bool get isRecording;

  Future<void> dispose();
}
