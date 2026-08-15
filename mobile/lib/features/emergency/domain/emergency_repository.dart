/// Dispatches an emergency alert to the backend.
///
/// **What this currently does:** creates an `Incident` row, stores the
/// location, broadcasts over the user's own WebSocket, and sends FCM to the
/// user's *own* devices.
///
/// **What it does not do, despite the name:** notify the emergency contacts.
/// `POST /api/v1/alerts/emergency` never reads the `emergency_contacts`
/// table — see `fastapi_app/routers/alerts.py`. Nor does it start evidence
/// recording or upload; nothing in the app imports the `record` package and
/// nothing calls `/api/v1/media`.
///
/// This comment previously claimed the opposite ("triggers emergency-contact
/// notification and evidence upload server-side"), which is the most
/// dangerous kind of wrong comment to leave in a safety app: it describes
/// FR-EMG-04 through FR-EMG-07 as done when the alert reaches nobody but the
/// person who triggered it. Tracked as the top gap in docs/SRS_STATUS.md.
///
/// See [EmergencyDispatchNotifier] for the offline-queue wrapping around
/// this call.
///
/// [latitude]/[longitude]/[accuracyMeters] are null when location wasn't
/// available at dispatch time (permission denied, GPS off, weak signal) —
/// dispatch must still proceed in that case, just without a location fix.
abstract class EmergencyRepository {
  Future<void> dispatchAlert({
    required String severity,
    required String summary,
    required bool auto,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  });
}
