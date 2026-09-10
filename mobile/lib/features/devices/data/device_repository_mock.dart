import '../domain/device_repository.dart';
import '../domain/models/device_detail.dart';

class DeviceRepositoryMock implements DeviceRepository {
  @override
  Future<List<DeviceDetail>> getDevices() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return const [
      DeviceDetail(
        id: 'ring',
        name: 'Smart Ring',
        type: DeviceType.ring,
        isOnline: true,
        batteryPercent: 0.82,
        batteryHoursRemaining: 36,
        signalStrength: 3,
        firmwareVersion: 'v2.4.1',
        updateAvailable: false,
        sensors: SensorReading(accelG: 1.02, gyroDps: 4.3, heartRateBpm: 0),
      ),
      DeviceDetail(
        id: 'glasses',
        name: 'Safety Glasses',
        type: DeviceType.glasses,
        isOnline: true,
        batteryPercent: 0.46,
        batteryHoursRemaining: 9,
        signalStrength: 2,
        firmwareVersion: 'v1.8.0',
        updateAvailable: true,
        sensors: SensorReading(accelG: 0.98, gyroDps: 2.1, heartRateBpm: 0),
      ),
      DeviceDetail(
        id: 'glove',
        name: 'Safety Glove',
        type: DeviceType.glove,
        isOnline: true,
        batteryPercent: 0.64,
        batteryHoursRemaining: 14,
        signalStrength: 3,
        firmwareVersion: 'v1.2.3',
        updateAvailable: false,
        sensors: SensorReading(accelG: 1.05, gyroDps: 6.7, heartRateBpm: 42),
      ),
      DeviceDetail(
        id: 'pendant',
        name: 'Pendant',
        type: DeviceType.pendant,
        isOnline: false,
        batteryPercent: 0.09,
        batteryHoursRemaining: 1,
        signalStrength: 0,
        firmwareVersion: 'v1.0.4',
        updateAvailable: true,
        sensors: SensorReading(accelG: 0, gyroDps: 0, heartRateBpm: 0),
      ),
    ];
  }

  @override
  Future<void> unpairDevice(String id) async {}
}
