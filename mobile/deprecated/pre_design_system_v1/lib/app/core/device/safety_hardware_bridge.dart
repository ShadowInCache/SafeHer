import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../shared/models/domain_models.dart';
import 'device_connectivity_service.dart';
import 'hardware_channel_gateway.dart';

abstract interface class SafetyHardwareBridge {
  List<String> get logs;

  Future<List<BluetoothDevice>> scanWearables({
    Duration timeout = const Duration(seconds: 10),
  });

  Future<bool> pairWearable({
    required DeviceKind kind,
    required BluetoothDevice device,
    Duration timeout = const Duration(seconds: 12),
  });

  Future<String> runDiagnostics(DeviceKind kind);

  Future<void> calibrate(DeviceKind kind);
}

class DeviceConnectivityHardwareBridge implements SafetyHardwareBridge {
  final DeviceConnectivityService _deviceConnectivityService;
  final HardwareChannelGateway? _hardwareChannelGateway;
  final bool _enableNativeBridge;
  final List<String> _nativeLogs = <String>[];

  DeviceConnectivityHardwareBridge(
    this._deviceConnectivityService, {
    HardwareChannelGateway? hardwareChannelGateway,
    bool enableNativeBridge = false,
  }) : _hardwareChannelGateway = hardwareChannelGateway,
       _enableNativeBridge = enableNativeBridge;

  @override
  List<String> get logs => [..._nativeLogs, ..._deviceConnectivityService.logs];

  void _addNativeLog(String message) {
    _nativeLogs.insert(0, '${DateTime.now().toIso8601String()} - $message');
    if (_nativeLogs.length > 100) {
      _nativeLogs.removeLast();
    }
  }

  @override
  Future<void> calibrate(DeviceKind kind) {
    return _deviceConnectivityService.calibrate(kind);
  }

  @override
  Future<bool> pairWearable({
    required DeviceKind kind,
    required BluetoothDevice device,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (_enableNativeBridge && _hardwareChannelGateway != null) {
      try {
        final response = await _hardwareChannelGateway.connectDevice(
          deviceId: device.remoteId.toString(),
        );
        _addNativeLog('Native connectDevice response: ${response['status']}');
      } catch (error) {
        _addNativeLog('Native connectDevice failed: $error');
      }
    }

    return _deviceConnectivityService.pairDevice(
      device: device,
      kind: kind,
      timeout: timeout,
    );
  }

  @override
  Future<String> runDiagnostics(DeviceKind kind) {
    return _deviceConnectivityService.runDiagnostics(kind);
  }

  @override
  Future<List<BluetoothDevice>> scanWearables({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_enableNativeBridge && _hardwareChannelGateway != null) {
      try {
        final response = await _hardwareChannelGateway.startBleScan(
          timeoutMs: timeout.inMilliseconds,
        );
        _addNativeLog('Native startBleScan response: ${response['status']}');
      } catch (error) {
        _addNativeLog('Native startBleScan failed: $error');
      }
    }

    return _deviceConnectivityService.scanForWearables(timeout: timeout);
  }
}
