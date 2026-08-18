import '../../../core/network/api_client.dart';
import '../domain/device_repository.dart';
import '../domain/models/device_detail.dart';

/// `fastapi_app`-backed [DeviceRepository] — `GET /api/v1/devices/me`.
///
/// Known gap: `DeviceDetail` still requires non-null battery/signal/
/// firmware/sensor values, but the backend only has real numbers for
/// battery/signal/firmware once a device has sent at least one heartbeat
/// (`POST /devices/{id}/heartbeat`), and has no REST concept of live
/// accel/gyro/flex readings at all (that's the live-monitoring WebSocket
/// feed, not this list endpoint). Until `DeviceDetail`'s telemetry fields
/// are made nullable (tracked alongside the real-BLE-pairing work), a
/// device that hasn't reported yet shows zeroed telemetry here rather than
/// invented numbers — genuinely "no data", just not yet surfaced as such
/// in the UI.
class DeviceRepositoryRemote implements DeviceRepository {
  DeviceRepositoryRemote({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// A device is "online" if it's sent a heartbeat recently — matches the
  /// backend's own `mqtt_stale_after_seconds` staleness window (see
  /// `fastapi_app/config.py`).
  static const _onlineWindow = Duration(seconds: 60);

  DeviceDetail _fromJson(Map<String, dynamic> json) {
    final lastSeenRaw = json['last_seen'] as String?;
    final lastSeen = lastSeenRaw != null ? DateTime.tryParse(lastSeenRaw) : null;
    final isOnline = lastSeen != null && DateTime.now().toUtc().difference(lastSeen.toUtc()) < _onlineWindow;
    final batteryLevel = json['battery_level'] as int?;

    return DeviceDetail(
      id: json['id'] as String,
      name: json['device_name'] as String,
      type: DeviceType.values.byName(_normalizeType(json['device_type'] as String)),
      isOnline: isOnline,
      batteryPercent: batteryLevel != null ? batteryLevel / 100 : 0,
      batteryHoursRemaining: 0,
      signalStrength: json['signal_strength'] as int? ?? 0,
      firmwareVersion: json['firmware_version'] as String? ?? 'Not reporting',
      updateAvailable: false,
      sensors: const SensorReading(accelG: 0, gyroDps: 0, flexPercent: 0),
      lastSeen: lastSeen,
    );
  }

  String _normalizeType(String type) {
    final lower = type.toLowerCase();
    return DeviceType.values.any((t) => t.name == lower) ? lower : 'ring';
  }

  @override
  Future<List<DeviceDetail>> getDevices() async {
    final response = await _apiClient.dio.get('/devices/me');
    return (response.data as List).cast<Map<String, dynamic>>().map(_fromJson).toList();
  }

  @override
  Future<void> unpairDevice(String id) async {
    await _apiClient.dio.delete<dynamic>('/devices/$id');
  }
}
