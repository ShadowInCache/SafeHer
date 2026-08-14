import '../../../core/network/api_client.dart';
import '../domain/home_repository.dart';
import '../domain/models/home_summary.dart';

/// `fastapi_app`-backed [HomeRepository] — `GET /api/v1/alerts/live`.
///
/// That endpoint is the only source of a "current" threat reading; it has
/// no per-modality (motion/audio/vision) breakdown, no live sensor preview
/// data, no gamified safety-score/streak concept, and no unread-alerts
/// inbox at all. Every one of those stays null/empty here rather than
/// being invented — see [HomeSummary]'s doc comment.
class HomeRepositoryRemote implements HomeRepository {
  HomeRepositoryRemote({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  @override
  Future<HomeSummary> getHomeSummary() async {
    final response = await _apiClient.dio.get('/alerts/live');
    final liveScore = response.data['live_score'] as Map<String, dynamic>?;
    final updatedAtRaw = liveScore?['updated_at'] as String?;
    // A null updated_at is the backend's own signal that no score has ever
    // been reported for this user — distinct from a genuine 0 reading.
    final updatedAt = updatedAtRaw != null ? DateTime.tryParse(updatedAtRaw) : null;
    final rawScore = (liveScore?['score'] as num?)?.toDouble();

    return HomeSummary(
      threat: updatedAt != null && rawScore != null
          ? ThreatSnapshot(score: (rawScore / 100).clamp(0.0, 1.0), lastUpdated: updatedAt)
          : null,
    );
  }
}
