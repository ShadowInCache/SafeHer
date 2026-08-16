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
/// Outcome of one dispatch, as reported by the server.
///
/// Both counts are nullable because a backend older than this client will
/// simply not send them, and "the server didn't say" must not be rendered as
/// "nobody was reached".
class DispatchOutcome {
  const DispatchOutcome({
    this.contactsTotal,
    this.contactsNotified,
    this.reachedContactIds = const [],
    this.incidentId,
  });

  /// The alert never left the device and is waiting in the offline queue.
  /// Distinct from a dispatch that ran and reached nobody.
  const DispatchOutcome.queued()
    : contactsTotal = null,
      contactsNotified = null,
      reachedContactIds = const [],
      incidentId = null;

  final int? contactsTotal;
  final int? contactsNotified;

  /// Ids of the contacts a channel actually accepted. The Emergency screen
  /// marks exactly these — anything else would be guessing which of her
  /// people know she needs help.
  final List<String> reachedContactIds;

  /// The incident the alert created. Null when the alert was queued
  /// offline — evidence has nothing to attach to until it actually sends.
  final String? incidentId;

  /// True when the alert was recorded but reached none of the contacts —
  /// the case the user most needs to know about, because it means she
  /// should find another way to get help.
  bool get reachedNobody => (contactsTotal ?? 0) > 0 && contactsNotified == 0;

  bool get reachedEveryone =>
      contactsTotal != null && contactsTotal! > 0 && contactsNotified == contactsTotal;
}

abstract class EmergencyRepository {
  Future<DispatchOutcome> dispatchAlert({
    required String severity,
    required String summary,
    required bool auto,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  });
}
