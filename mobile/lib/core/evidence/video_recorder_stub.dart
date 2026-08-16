import 'evidence_recorder.dart';
import 'video_recorder.dart';

/// Web build: reports unsupported rather than half-working.
///
/// The browser can capture video, but the surrounding evidence path is
/// built around bytes read off disk and encrypted server-side. Claiming
/// support and failing at upload time would be worse than saying so up
/// front — the same call made for audio and for BLE pairing.
class PlatformVideoRecorder implements VideoEvidenceRecorder {
  @override
  bool get isRecording => false;

  @override
  Future<bool> isSupported() async => false;

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> start() async {
    throw const EvidenceRecorderException(EvidenceRecorderFailure.unsupported);
  }

  @override
  Future<EvidenceRecording?> stop() async => null;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}
