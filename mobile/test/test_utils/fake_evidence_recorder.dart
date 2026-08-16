import 'dart:typed_data';

import 'package:safeher_app/core/evidence/evidence_recorder.dart';
import 'package:safeher_app/features/emergency/domain/evidence_repository.dart';

/// Stands in for the microphone.
class FakeEvidenceRecorder implements EvidenceRecorder {
  FakeEvidenceRecorder({
    this.supported = true,
    this.startFailure,
    EvidenceRecording? recording,
    this.producesNothing = false,
  }) : recording = recording ?? sampleRecording;

  /// When true, [stop] returns null — the recorder ran but captured nothing.
  final bool producesNothing;

  final bool supported;

  /// When set, [start] throws it.
  final EvidenceRecorderException? startFailure;

  /// What [stop] hands back when [producesNothing] is false.
  final EvidenceRecording recording;

  var startCalls = 0;
  var stopCalls = 0;
  var cancelCalls = 0;
  bool _isRecording = false;

  @override
  bool get isRecording => _isRecording;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> hasPermission() async => supported;

  @override
  Future<bool> requestPermission() async => supported;

  @override
  Future<void> start() async {
    startCalls++;
    final failure = startFailure;
    if (failure != null) throw failure;
    _isRecording = true;
  }

  @override
  Future<EvidenceRecording?> stop() async {
    stopCalls++;
    _isRecording = false;
    return producesNothing ? null : recording;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    _isRecording = false;
  }

  @override
  Future<void> dispose() async {}
}

final sampleRecording = EvidenceRecording(
  mimeType: 'audio/mp4',
  bytes: Uint8List.fromList(List<int>.filled(64, 7)),
);

/// Records what was uploaded, and can be made to fail.
class FakeEvidenceRepository implements EvidenceRepository {
  FakeEvidenceRepository({this.shouldFail = false});

  final bool shouldFail;
  final uploads = <String>[];

  @override
  Future<String> upload({
    required String incidentId,
    required EvidenceRecording recording,
  }) async {
    if (shouldFail) throw Exception('upload failed');
    uploads.add(incidentId);
    return 'evidence-${uploads.length}';
  }
}
