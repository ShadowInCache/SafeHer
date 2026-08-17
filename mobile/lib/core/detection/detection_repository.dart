import 'package:dio/dio.dart';

import '../network/api_client.dart';
import 'detection_status.dart';

/// Reads the detection pipeline's real state from the backend.
///
/// `GET /api/v1/alerts/models` is the server's own account of which models
/// are serving. Asking it, rather than assuming, is what keeps the Profile
/// screen honest when the answer changes — the day the first model is
/// trained, the app says so without a release.
abstract class DetectionRepository {
  Future<DetectionStatus> fetchStatus();
}

class DetectionRepositoryRemote implements DetectionRepository {
  DetectionRepositoryRemote({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  @override
  Future<DetectionStatus> fetchStatus() async {
    try {
      final response = await _apiClient.dio.get('/alerts/models');
      final data = response.data;
      if (data is Map<String, dynamic>) return DetectionStatus.fromJson(data);
      return DetectionStatus.unknown;
    } on DioException {
      // Offline, or an older backend without this endpoint. Falling back to
      // `unknown` states that detection is off, which is the safe direction
      // to be wrong in: it never tells someone help is coming on its own.
      return DetectionStatus.unknown;
    }
  }
}

/// Used by widget tests and the mock flavour.
class DetectionRepositoryFake implements DetectionRepository {
  DetectionRepositoryFake(this._status);

  final DetectionStatus _status;

  @override
  Future<DetectionStatus> fetchStatus() async => _status;
}
