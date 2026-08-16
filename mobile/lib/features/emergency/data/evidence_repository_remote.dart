import 'package:dio/dio.dart';

import '../../../core/evidence/evidence_recorder.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/evidence_repository.dart';

/// `fastapi_app`-backed [EvidenceRepository] —
/// `POST /api/v1/media/evidence/{incidentId}`.
///
/// The server encrypts at rest and serves the recording back only to its
/// owner, so no public URL comes back here — just the id (see
/// `fastapi_app/services/evidence_store.py`).
class EvidenceRepositoryRemote implements EvidenceRepository {
  const EvidenceRepositoryRemote({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  @override
  Future<String> upload({
    required String incidentId,
    required EvidenceRecording recording,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          recording.bytes,
          filename: 'evidence.m4a',
          // The server validates against an allow-list, so the type has to
          // be stated rather than left for Dio to guess from the filename.
          contentType: DioMediaType.parse(recording.mimeType),
        ),
      });
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/media/evidence/$incidentId',
        data: form,
      );
      final id = response.data?['id'] as String?;
      if (id == null) {
        throw const ApiException(message: 'The server stored no evidence. Please try again.');
      }
      return id;
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }
}
