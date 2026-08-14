import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'location_result.dart';

/// Thin wrapper around `geolocator` that never throws — every failure mode
/// (permission denied, services off, weak signal) resolves to a typed
/// [LocationUnavailable] instead, so callers (the Emergency flow above all)
/// can always proceed with dispatch rather than being blocked by GPS state.
class LocationService {
  Future<LocationResult> getCurrentLocation({Duration timeLimit = const Duration(seconds: 8)}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationUnavailable(LocationFailureReason.serviceDisabled);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return const LocationUnavailable(LocationFailureReason.permissionDenied);
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationUnavailable(LocationFailureReason.permissionDeniedForever);
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: timeLimit,
      );
      return LocationAvailable(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );
    } on LocationServiceDisabledException {
      return const LocationUnavailable(LocationFailureReason.serviceDisabled);
    } on TimeoutException {
      // Weak/no signal (indoors, underground, etc.) — the failure mode the
      // spec explicitly calls out to handle gracefully rather than block on.
      return const LocationUnavailable(LocationFailureReason.timeout);
    } catch (_) {
      return const LocationUnavailable(LocationFailureReason.unavailable);
    }
  }
}
