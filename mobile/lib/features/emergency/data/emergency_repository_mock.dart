import '../domain/emergency_repository.dart';

/// Simulates a dispatch — used in mock API mode, where the UI is being
/// explored without a backend.
///
/// Models the *asynchronous* fan-out the real backend now does: the first
/// answer says the dispatch has started and has reached nobody yet, and the
/// outcome only appears once [fetchDispatchStatus] is polled. A mock that
/// returned the final result immediately would hide the pending state, which
/// is precisely the state the Emergency screen used to get wrong.
class EmergencyRepositoryMock implements EmergencyRepository {
  int _polls = 0;

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
    await Future.delayed(const Duration(milliseconds: 300));
    _polls = 0;
    return DispatchOutcome(
      contactsTotal: 3,
      contactsNotified: 0,
      reachedContactIds: const [],
      failedContactIds: const [],
      incidentId: incidentId ?? 'mock-incident-1',
      progress: DispatchProgress.inProgress,
    );
  }

  @override
  Future<DispatchOutcome> fetchDispatchStatus(String incidentId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    _polls++;

    // First poll: still working. Contacts show as "Sending…".
    if (_polls < 2) {
      return DispatchOutcome(
        contactsTotal: 3,
        contactsNotified: 1,
        reachedContactIds: const ['1'],
        incidentId: incidentId,
        progress: DispatchProgress.inProgress,
      );
    }

    // Settled. Two of three, not three of three: the "some contacts could
    // not be reached" path is the one most likely to be mishandled, so mock
    // mode shows it by default rather than hiding it behind a perfect run.
    return DispatchOutcome(
      contactsTotal: 3,
      contactsNotified: 2,
      reachedContactIds: const ['1', '2'],
      failedContactIds: const ['3'],
      incidentId: incidentId,
      progress: DispatchProgress.complete,
    );
  }
}
