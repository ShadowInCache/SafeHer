import 'package:safeher_app/core/location/location_result.dart';
import 'package:safeher_app/core/location/location_service.dart';

/// Stand-in for [LocationService] so widget tests never reach geolocator's
/// platform channel — an unoverridden location lookup in a test leaves real
/// pending work behind and fails the timer invariant.
class FakeLocationService implements LocationService {
  FakeLocationService([this.result = defaultFix]);

  static const defaultFix = LocationAvailable(
    latitude: 12.9716,
    longitude: 77.5946,
    accuracyMeters: 8,
  );

  final LocationResult result;

  @override
  Future<LocationResult> getCurrentLocation({Duration timeLimit = const Duration(seconds: 8)}) async =>
      result;
}
