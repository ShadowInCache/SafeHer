import 'evidence_recorder.dart';

/// Web build: reports unsupported rather than half-working.
///
/// `record` does have a web implementation, but it yields a blob URL rather
/// than a file, and the upload path here is built around bytes read from
/// disk. Claiming support and then failing at upload time would be worse
/// than saying so up front — the same call made for BLE pairing.
class PlatformEvidenceRecorder implements EvidenceRecorder {
  @override
  bool get isRecording => false;

  @override
  Future<bool> isSupported() async => false;

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> start() async =>
      throw const EvidenceRecorderException(EvidenceRecorderFailure.unsupported);

  @override
  Future<EvidenceRecording?> stop() async => null;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}
