import '../../../core/network/api_client.dart';
import '../domain/emergency_repository.dart';

/// `fastapi_app`-backed [EmergencyRepository] — `POST /api/v1/alerts/emergency`.
///
/// Creates a real `Incident` row, stores the location, broadcasts over the
/// alerts WebSocket, and — since `emergency_dispatch.py` landed — fans the
/// alert out to the user's emergency contacts over SMS and, where a contact
/// is themselves a SafeHer user, push. The response carries how many of them
/// were actually reached, which this returns rather than discards.
class EmergencyRepositoryRemote implements EmergencyRepository {
  EmergencyRepositoryRemote({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  @override
  Future<DispatchOutcome> dispatchAlert({
    required String severity,
    required String summary,
    required bool auto,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
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

    final data = response.data ?? const <String, dynamic>{};
    return DispatchOutcome(
      contactsTotal: (data['contacts_total'] as num?)?.toInt(),
      contactsNotified: (data['contacts_notified'] as num?)?.toInt(),
      reachedContactIds:
          (data['contacts_reached'] as List<dynamic>? ?? const []).cast<String>(),
      incidentId: data['id'] as String?,
    );
  }
}
