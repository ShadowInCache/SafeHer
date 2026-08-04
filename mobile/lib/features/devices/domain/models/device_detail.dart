enum DeviceType { ring, glasses, glove, pendant }

class SensorReading {
  const SensorReading({required this.accelG, required this.gyroDps, required this.flexPercent});

  final double accelG;
  final double gyroDps;
  final double flexPercent;
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
}
