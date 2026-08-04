import 'models/device_detail.dart';

abstract class DeviceRepository {
  Future<List<DeviceDetail>> getDevices();
}
