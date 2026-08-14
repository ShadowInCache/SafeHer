/// Dispatches an emergency alert to the backend — creates an incident,
/// which triggers emergency-contact notification and evidence upload
/// server-side. See [EmergencyDispatchNotifier] for the offline-queue
/// wrapping around this call.
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
