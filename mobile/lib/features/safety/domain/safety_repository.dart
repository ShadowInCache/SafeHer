import 'models/nearby_place.dart';
import 'models/safe_journey.dart';
import 'models/safety_settings.dart';

/// Raised when the nearby-places data source is reachable but over quota.
/// Distinct from a generic failure so the UI can say "try again in a moment"
/// rather than implying the area has no police stations.
class NearbyRateLimitedException implements Exception {
  const NearbyRateLimitedException();
}

abstract interface class SafetyRepository {
  Future<SafetyPreferences> getPreferences();
  Future<SafetyPreferences> updatePreferences(SafetyPreferences preferences);

  Future<SafetyPinStatus> getPinStatus();
  Future<void> setPin({required String pin, String? currentPin});
  Future<void> removePin(String pin);
  Future<PinVerificationResult> verifyPin(String pin);

  /// Real places near [latitude]/[longitude]. Returns an empty list only when
  /// there genuinely is nothing in range.
  Future<List<NearbyPlace>> findNearby({
    required double latitude,
    required double longitude,
    int radiusMetres,
    List<NearbyPlaceCategory>? categories,
  });
}

abstract interface class JourneyRepository {
  Future<SafeJourney?> getActiveJourney();
  Future<List<SafeJourney>> listJourneys();
  Future<SafeJourney> startJourney({
    required String destinationLabel,
    required int expectedDurationMinutes,
    double? destinationLat,
    double? destinationLng,
    int? checkInIntervalMinutes,
    List<String> contactIds,
  });
  Future<void> pushLocation({
    required String journeyId,
    required double latitude,
    required double longitude,
    double? accuracyMetres,
  });
  Future<List<JourneyBreadcrumb>> getBreadcrumbs(String journeyId);
  Future<SafeJourney> checkIn(String journeyId);
  Future<SafeJourney> markArrived(String journeyId);
  Future<SafeJourney> cancel(String journeyId);
  Future<SafeJourney> escalate(String journeyId);
}
