import 'models/device_detail.dart';

abstract class DeviceRepository {
  Future<List<DeviceDetail>> getDevices();

  /// Removes a wearable from the account.
  ///
  /// Until this existed a device paired once stayed registered forever: the
  /// app could drop the Bluetooth link locally, and the server still listed
  /// the wearable. Someone who had given a glove away, or had one taken, had
  /// no way to say so — and its push tokens kept receiving her emergency
  /// notifications.
  Future<void> unpairDevice(String id);
}
