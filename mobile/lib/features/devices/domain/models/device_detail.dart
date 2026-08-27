enum DeviceType { ring, glasses, glove, pendant }

class SensorReading {
  const SensorReading({
    required this.accelG,
    required this.gyroDps,
    required this.heartRateBpm,
  });

  /// Nothing has been heard from the device yet.
  ///
  /// Distinct from a reading of zero on purpose: the card used to show
  /// `0.00g / 0.0 deg/s / 0%` whether the glove was silent or genuinely
  /// still, and "0 bpm" is a claim about someone's heart that this app
  /// should never make by accident.
  const SensorReading.unknown()
      : accelG = null,
        gyroDps = null,
        heartRateBpm = null;

  final double? accelG;
  final double? gyroDps;

  /// Beats per minute from the glove's pulse sensor. Replaces the flex
  /// reading, which no hardware on the glove ever produced.
  final double? heartRateBpm;

  bool get hasAny => accelG != null || gyroDps != null || heartRateBpm != null;
}

class DeviceDetail {
  const DeviceDetail({
    required this.id,
    required this.name,
    required this.type,
    required this.isOnline,
    required this.batteryPercent,
    required this.batteryHoursRemaining,
    required this.signalStrength,
    required this.firmwareVersion,
    required this.updateAvailable,
    required this.sensors,
    this.lastSeen,
  });

  final String id;
  final String name;
  final DeviceType type;
  final bool isOnline;
  final double batteryPercent;
  final int batteryHoursRemaining;
  final int signalStrength;
  final String firmwareVersion;
  final bool updateAvailable;
  final SensorReading sensors;

  /// When the backend last heard from this device (`last_seen` in
  /// `fastapi_app/schemas.py`'s `DevicePublic`) — null if it's never sent
  /// a heartbeat.
  final DateTime? lastSeen;
}
