import '../domain/models/nearby_place.dart';
import '../domain/models/safe_journey.dart';
import '../domain/models/safety_settings.dart';
import '../domain/safety_repository.dart';

/// Fixture-backed implementations used **only** under
/// `--dart-define=USE_MOCK_API=true`, for UI work without a backend running.
/// `AppConfig.useMockApi` is false by default, so production paths never
/// reach this file.
class SafetyRepositoryMock implements SafetyRepository {
  SafetyPreferences _preferences = const SafetyPreferences.defaults();
  String? _pin;

  @override
  Future<SafetyPreferences> getPreferences() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _preferences;
  }

  @override
  Future<SafetyPreferences> updatePreferences(SafetyPreferences preferences) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    _preferences = preferences;
    return _preferences;
  }

  @override
  Future<SafetyPinStatus> getPinStatus() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return SafetyPinStatus(isSet: _pin != null);
  }

  @override
  Future<void> setPin({required String pin, String? currentPin}) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _pin = pin;
  }

  @override
  Future<void> removePin(String pin) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _pin = null;
  }

  @override
  Future<PinVerificationResult> verifyPin(String pin) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return PinVerificationResult(valid: _pin != null && pin == _pin, attemptsRemaining: 4);
  }

  @override
  Future<List<NearbyPlace>> findNearby({
    required double latitude,
    required double longitude,
    int radiusMetres = 3000,
    List<NearbyPlaceCategory>? categories,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // Offsets from the caller's real position so the mock flavour still
    // renders a plausible list; never used when useMockApi is false.
    return [
      NearbyPlace(
        id: 'mock/1',
        name: 'City Police Station',
        category: NearbyPlaceCategory.police,
        latitude: latitude + 0.004,
        longitude: longitude + 0.002,
        distanceMetres: 480,
        phone: '+10000000000',
      ),
      NearbyPlace(
        id: 'mock/2',
        name: 'General Hospital',
        category: NearbyPlaceCategory.hospital,
        latitude: latitude - 0.006,
        longitude: longitude + 0.005,
        distanceMetres: 890,
      ),
    ];
  }
}

class JourneyRepositoryMock implements JourneyRepository {
  SafeJourney? _active;
  final List<SafeJourney> _history = [];

  @override
  Future<SafeJourney?> getActiveJourney() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _active;
  }

  @override
  Future<List<SafeJourney>> listJourneys() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return [if (_active != null) _active!, ..._history];
  }

  @override
  Future<SafeJourney> startJourney({
    required String destinationLabel,
    required int expectedDurationMinutes,
    double? destinationLat,
    double? destinationLng,
    int? checkInIntervalMinutes,
    List<String> contactIds = const [],
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final now = DateTime.now();
    _active = SafeJourney(
      id: 'mock-journey-${now.microsecondsSinceEpoch}',
      destinationLabel: destinationLabel,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      expectedDurationMinutes: expectedDurationMinutes,
      checkInIntervalMinutes: checkInIntervalMinutes,
      status: JourneyStatus.active,
      startedAt: now,
      expectedArrivalAt: now.add(Duration(minutes: expectedDurationMinutes)),
      contactIds: contactIds,
    );
    return _active!;
  }

  @override
  Future<void> pushLocation({
    required String journeyId,
    required double latitude,
    required double longitude,
    double? accuracyMetres,
  }) async {}

  @override
  Future<List<JourneyBreadcrumb>> getBreadcrumbs(String journeyId) async => const [];

  @override
  Future<SafeJourney> checkIn(String journeyId) async => _active!;

  @override
  Future<SafeJourney> markArrived(String journeyId) => _end(JourneyStatus.arrived);

  @override
  Future<SafeJourney> cancel(String journeyId) => _end(JourneyStatus.cancelled);

  @override
  Future<SafeJourney> escalate(String journeyId) async => _active!;

  Future<SafeJourney> _end(JourneyStatus status) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final current = _active!;
    final ended = SafeJourney(
      id: current.id,
      destinationLabel: current.destinationLabel,
      destinationLat: current.destinationLat,
      destinationLng: current.destinationLng,
      expectedDurationMinutes: current.expectedDurationMinutes,
      checkInIntervalMinutes: current.checkInIntervalMinutes,
      status: status,
      startedAt: current.startedAt,
      expectedArrivalAt: current.expectedArrivalAt,
      lastCheckInAt: current.lastCheckInAt,
      endedAt: DateTime.now(),
      contactIds: current.contactIds,
    );
    _history.insert(0, ended);
    _active = null;
    return ended;
  }
}
