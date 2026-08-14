import 'package:safeher_app/features/safety/domain/models/nearby_place.dart';
import 'package:safeher_app/features/safety/domain/models/safe_journey.dart';
import 'package:safeher_app/features/safety/domain/models/safety_settings.dart';
import 'package:safeher_app/features/safety/domain/safety_repository.dart';

/// Controllable [SafetyRepository] for widget tests.
class FakeSafetyRepository implements SafetyRepository {
  FakeSafetyRepository({
    List<NearbyPlace>? places,
    this.error,
    this.preferences = const SafetyPreferences.defaults(),
    this.pinStatus = const SafetyPinStatus(isSet: false),
    this.verifyResult = const PinVerificationResult(valid: true),
    this.delay = const Duration(milliseconds: 50),
  }) : places = places ?? const [];

  final List<NearbyPlace> places;
  final Object? error;
  SafetyPreferences preferences;
  final SafetyPinStatus pinStatus;
  final PinVerificationResult verifyResult;
  final Duration delay;

  final List<String> verifiedPins = [];

  @override
  Future<List<NearbyPlace>> findNearby({
    required double latitude,
    required double longitude,
    int radiusMetres = 3000,
    List<NearbyPlaceCategory>? categories,
  }) async {
    await Future<void>.delayed(delay);
    if (error != null) throw error!;
    return places;
  }

  @override
  Future<SafetyPreferences> getPreferences() async {
    await Future<void>.delayed(delay);
    if (error != null) throw error!;
    return preferences;
  }

  @override
  Future<SafetyPreferences> updatePreferences(SafetyPreferences updated) async {
    await Future<void>.delayed(delay);
    preferences = updated;
    return preferences;
  }

  @override
  Future<SafetyPinStatus> getPinStatus() async {
    await Future<void>.delayed(delay);
    return pinStatus;
  }

  @override
  Future<void> setPin({required String pin, String? currentPin}) async {
    await Future<void>.delayed(delay);
  }

  @override
  Future<void> removePin(String pin) async {
    await Future<void>.delayed(delay);
  }

  @override
  Future<PinVerificationResult> verifyPin(String pin) async {
    await Future<void>.delayed(delay);
    verifiedPins.add(pin);
    return verifyResult;
  }
}

/// Controllable [JourneyRepository] for widget tests.
class FakeJourneyRepository implements JourneyRepository {
  FakeJourneyRepository({this.active, this.delay = const Duration(milliseconds: 50)});

  SafeJourney? active;
  final Duration delay;

  final List<String> calls = [];

  @override
  Future<SafeJourney?> getActiveJourney() async {
    await Future<void>.delayed(delay);
    return active;
  }

  @override
  Future<List<SafeJourney>> listJourneys() async => [if (active != null) active!];

  @override
  Future<SafeJourney> startJourney({
    required String destinationLabel,
    required int expectedDurationMinutes,
    double? destinationLat,
    double? destinationLng,
    int? checkInIntervalMinutes,
    List<String> contactIds = const [],
  }) async {
    calls.add('start:$destinationLabel:$expectedDurationMinutes');
    final now = DateTime.now();
    return active = SafeJourney(
      id: 'journey-1',
      destinationLabel: destinationLabel,
      expectedDurationMinutes: expectedDurationMinutes,
      checkInIntervalMinutes: checkInIntervalMinutes,
      status: JourneyStatus.active,
      startedAt: now,
      expectedArrivalAt: now.add(Duration(minutes: expectedDurationMinutes)),
      contactIds: contactIds,
    );
  }

  @override
  Future<void> pushLocation({
    required String journeyId,
    required double latitude,
    required double longitude,
    double? accuracyMetres,
  }) async {
    calls.add('location:$journeyId');
  }

  @override
  Future<List<JourneyBreadcrumb>> getBreadcrumbs(String journeyId) async => const [];

  @override
  Future<SafeJourney> checkIn(String journeyId) async {
    calls.add('check-in:$journeyId');
    return active!;
  }

  @override
  Future<SafeJourney> markArrived(String journeyId) async {
    calls.add('arrive:$journeyId');
    return active!;
  }

  @override
  Future<SafeJourney> cancel(String journeyId) async {
    calls.add('cancel:$journeyId');
    return active!;
  }

  @override
  Future<SafeJourney> escalate(String journeyId) async {
    calls.add('escalate:$journeyId');
    return active!;
  }
}
