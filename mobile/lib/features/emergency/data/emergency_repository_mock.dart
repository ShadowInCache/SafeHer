import '../domain/emergency_repository.dart';

/// Simulates a successful dispatch to the backend after a short delay —
/// used whenever mock API mode is active (currently always, since there's
/// no live SafeHer backend yet).
class EmergencyRepositoryMock implements EmergencyRepository {
  @override
  Future<void> dispatchAlert({
    required String severity,
    required String summary,
    required bool auto,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
  }
}
