import '../../../core/network/api_client.dart';
import '../domain/emergency_repository.dart';

/// `fastapi_app`-backed [EmergencyRepository] — `POST /api/v1/alerts/emergency`.
/// Creates a real `Incident` row, broadcasts over the alerts WebSocket, and
/// best-effort pushes FCM to the user's registered devices server-side (see
/// repo root API.md and `fastapi_app/routers/alerts.py`).
class EmergencyRepositoryRemote implements EmergencyRepository {
  EmergencyRepositoryRemote({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  @override
  Future<void> dispatchAlert({
    required String severity,
    required String summary,
    required bool auto,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  }) async {
    await _apiClient.dio.post(
      '/alerts/emergency',
      data: {
        'auto': auto,
        'severity': severity,
        'summary': summary,
        // The backend's `location` field is required but untyped beyond
        // "dict of floats" — an empty map is how "no GPS fix at dispatch
        // time" is represented honestly, rather than fabricating
        // coordinates. Keys must be `latitude`/`longitude`/`accuracy` —
        // that's what `fastapi_app/routers/alerts.py` actually reads
        // (`loc.get("latitude", ...)`); `lat`/`lng` would silently be
        // ignored and default to 0.0, 0.0.
        'location': {
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          if (accuracyMeters != null) 'accuracy': accuracyMeters,
        },
      },
    );
  }
}
