import '../domain/emergency_repository.dart';

/// Simulates a successful dispatch after a short delay — used in mock API
/// mode, where the UI is being explored without a backend.
class EmergencyRepositoryMock implements EmergencyRepository {
  @override
  Future<DispatchOutcome> dispatchAlert({
    required String severity,
    required String summary,
    required bool auto,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    // Two of three, not three of three: the "some contacts could not be
    // reached" path is the one most likely to be mishandled, so mock mode
    // shows it by default rather than hiding it behind a perfect run.
    return const DispatchOutcome(
      contactsTotal: 3,
      contactsNotified: 2,
      reachedContactIds: ['1', '2'],
    );
  }
}
