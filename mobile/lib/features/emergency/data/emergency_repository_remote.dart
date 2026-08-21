import '../../../core/network/api_client.dart';
import '../domain/emergency_repository.dart';

/// `fastapi_app`-backed [EmergencyRepository] — `POST /api/v1/alerts/emergency`.
///
/// Creates a real `Incident` row, stores the location, broadcasts over the
/// alerts WebSocket, and queues the fan-out to the user's emergency contacts.
/// The response reports that the fan-out has *started*; who it reached is read
/// back from `GET /alerts/emergency/{id}/dispatch`.
class EmergencyRepositoryRemote implements EmergencyRepository {
  EmergencyRepositoryRemote({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  @override
  Future<DispatchOutcome> dispatchAlert({
    required String severity,
    required String summary,
    required bool auto,
    String? incidentId,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/alerts/emergency',
      data: {
        // The id the client chose, so a retry after a timeout resolves to the
        // same incident instead of filing a second emergency.
        if (incidentId != null) 'incident_id': incidentId,
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
    return _outcomeFrom(data, fallbackIncidentId: incidentId);
  }

  @override
  Future<DispatchOutcome> fetchDispatchStatus(String incidentId) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/alerts/emergency/$incidentId/dispatch',
    );
    final data = response.data ?? const <String, dynamic>{};
    return _outcomeFrom(data, fallbackIncidentId: incidentId);
  }

  /// Both endpoints describe the same thing, so they are read the same way.
  ///
  /// The status field is named `dispatch_status` on the incident body and
  /// `status` on the poll body; both are accepted rather than adding a second
  /// parser that could drift from this one.
  DispatchOutcome _outcomeFrom(
    Map<String, dynamic> data, {
    String? fallbackIncidentId,
  }) {
    final rawStatus = (data['dispatch_status'] ?? data['status']) as String?;
    return DispatchOutcome(
      contactsTotal: (data['contacts_total'] as num?)?.toInt(),
      contactsNotified: (data['contacts_notified'] as num?)?.toInt(),
      reachedContactIds: _ids(data['contacts_reached']),
      failedContactIds: _ids(data['contacts_failed']),
      incidentId: (data['id'] ?? data['incident_id']) as String? ?? fallbackIncidentId,
      progress: _progressFrom(rawStatus),
    );
  }

  /// An unrecognised or absent status resolves to [DispatchProgress.complete].
  ///
  /// That is the conservative reading against an older backend that does not
  /// send the field: it means unreached contacts are shown as unreachable
  /// rather than spinning on "Sending…" forever, which is the failure this
  /// whole change exists to remove. Over-reporting a failure prompts the user
  /// to find another way to get help; under-reporting one tells her help is
  /// coming when it is not.
  DispatchProgress _progressFrom(String? status) => switch (status) {
    'in_progress' => DispatchProgress.inProgress,
    'failed' => DispatchProgress.failed,
    _ => DispatchProgress.complete,
  };

  List<String> _ids(Object? raw) =>
      raw is List ? raw.map((item) => item.toString()).toList() : const [];
}
