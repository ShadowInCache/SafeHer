import '../../../core/evidence/evidence_recorder.dart';

/// Uploads a finished [EvidenceRecording] against an incident.
abstract class EvidenceRepository {
  /// Returns the server-side media id.
  ///
  /// Throws on failure rather than returning null: the caller decides
  /// whether a failed upload is worth telling the user about, and silently
  /// swallowing it would leave her believing evidence was captured.
  Future<String> upload({
    required String incidentId,
    required EvidenceRecording recording,
  });
}
