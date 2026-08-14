/// Outcome of a location fetch attempt. Modeled explicitly (rather than
/// just throwing) because the Emergency flow needs to keep working and
/// dispatch the alert even when location isn't available — a GPS glitch
/// must never block an SOS.
sealed class LocationResult {
  const LocationResult();
}

class LocationAvailable extends LocationResult {
  const LocationAvailable({required this.latitude, required this.longitude, required this.accuracyMeters});

  final double latitude;
  final double longitude;
  final double accuracyMeters;
}

enum LocationFailureReason {
  /// The user denied the permission prompt this time — asking again later
  /// (e.g. next SOS) is allowed.
  permissionDenied,

  /// The user denied permanently ("don't ask again") — only a system
  /// settings visit can restore it.
  permissionDeniedForever,

  /// Device location services (GPS/Wi-Fi positioning) are switched off
  /// entirely, independent of the app's own permission.
  serviceDisabled,

  /// Permission was granted and services are on, but no fix arrived
  /// within the timeout — weak/no signal (indoors, underground, etc.).
  timeout,

  /// Anything else geolocator surfaced (unsupported platform, plugin
  /// error) that doesn't fit a more specific category above.
  unavailable,
}

class LocationUnavailable extends LocationResult {
  const LocationUnavailable(this.reason);

  final LocationFailureReason reason;

  String get userMessage => switch (reason) {
    LocationFailureReason.permissionDenied => 'Location permission needed to share your position.',
    LocationFailureReason.permissionDeniedForever => 'Location permission denied — enable it in system settings.',
    LocationFailureReason.serviceDisabled => 'Turn on location services to share your position.',
    LocationFailureReason.timeout => 'Location signal is weak — dispatching without it.',
    LocationFailureReason.unavailable => 'Location unavailable — dispatching without it.',
  };
}
