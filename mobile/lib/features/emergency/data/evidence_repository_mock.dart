import '../../../core/evidence/evidence_recorder.dart';
import '../domain/evidence_repository.dart';

class EvidenceRepositoryMock implements EvidenceRepository {
  final uploads = <String>[];

  @override
  Future<String> upload({
    required String incidentId,
    required EvidenceRecording recording,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    uploads.add(incidentId);
    return 'mock-evidence-${uploads.length}';
  }
}
