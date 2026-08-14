import 'device_detail.dart';

/// A device the backend has on record for the signed-in user — the shape
/// of `DevicePublic` in `fastapi_app/schemas.py`, narrowed to the fields
/// the pairing flow actually uses.
class RegisteredDevice {
  const RegisteredDevice({
    required this.id,
    required this.deviceName,
    required this.deviceType,
    required this.isActive,
  });

  final String id;
  final String deviceName;
  final DeviceType deviceType;
  final bool isActive;

  factory RegisteredDevice.fromJson(Map<String, dynamic> json) {
    return RegisteredDevice(
      id: json['id'] as String,
      deviceName: json['device_name'] as String? ?? '',
      deviceType: deviceTypeFromWireName(json['device_type'] as String?),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

/// `device_type` is an unconstrained string column on the backend
/// (`fastapi_app/models.py`), so an unrecognised value is possible — fall
/// back rather than throwing mid-pairing.
DeviceType deviceTypeFromWireName(String? name) {
  for (final type in DeviceType.values) {
    if (type.name == name) return type;
  }
  return DeviceType.ring;
}

extension DeviceTypeLabel on DeviceType {
  /// Human-facing label for the device-type picker.
  String get label => switch (this) {
    DeviceType.ring => 'Ring',
    DeviceType.glasses => 'Glasses',
    DeviceType.glove => 'Glove',
    DeviceType.pendant => 'Pendant',
  };
}
