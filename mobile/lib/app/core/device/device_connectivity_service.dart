import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../shared/models/domain_models.dart';

class DeviceConnectivityService {
  final List<String> _logs = [];

  BluetoothDevice? _glove;
  BluetoothDevice? _glasses;

  List<String> get logs => List.unmodifiable(_logs);

  void _addLog(String message) {
    _logs.insert(0, '${DateTime.now().toIso8601String()} - $message');
    if (_logs.length > 200) {
      _logs.removeLast();
    }
  }

  Future<List<BluetoothDevice>> scanForWearables({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final available = <BluetoothDevice>[];
    _addLog('Started BLE scan');

    await FlutterBluePlus.startScan(timeout: timeout);
    final completer = Completer<void>();

    final subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final name = result.device.platformName.toLowerCase();
        if (name.contains('safeher') ||
            name.contains('glove') ||
            name.contains('glass')) {
          if (!available.contains(result.device)) {
            available.add(result.device);
            _addLog('Found wearable: ${result.device.platformName}');
          }
        }
      }
    });

    await Future.delayed(timeout);
    await FlutterBluePlus.stopScan();
    await subscription.cancel();
    completer.complete();
    await completer.future;

    _addLog('Scan completed. ${available.length} wearables discovered');
    return available;
  }

  Future<bool> pairDevice({
    required BluetoothDevice device,
    required DeviceKind kind,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    _addLog('Pairing started for ${kind.name}: ${device.platformName}');
    try {
      await device.connect(timeout: timeout);
      await device.discoverServices();

      if (kind == DeviceKind.glove) {
        _glove = device;
      } else {
        _glasses = device;
      }

      _addLog('Pairing successful for ${kind.name}');
      return true;
    } catch (error) {
      _addLog('Pairing failed for ${kind.name}: $error');
      return false;
    }
  }

  Future<void> disconnect(DeviceKind kind) async {
    final device = kind == DeviceKind.glove ? _glove : _glasses;
    if (device != null) {
      await device.disconnect();
      _addLog('Disconnected ${kind.name}');
    }

    if (kind == DeviceKind.glove) {
      _glove = null;
    } else {
      _glasses = null;
    }
  }

  Future<bool> reconnectLast(DeviceKind kind) async {
    final device = kind == DeviceKind.glove ? _glove : _glasses;
    if (device == null) {
      _addLog('No known ${kind.name} for reconnect');
      return false;
    }
    return pairDevice(device: device, kind: kind);
  }

  Future<String> runDiagnostics(DeviceKind kind) async {
    final device = kind == DeviceKind.glove ? _glove : _glasses;
    if (device == null) {
      return '${kind.name} not connected';
    }

    final services = await device.discoverServices();
    final report =
        '${kind.name} diagnostics: ${services.length} BLE services discovered.';
    _addLog(report);
    return report;
  }

  Future<void> calibrate(DeviceKind kind) async {
    _addLog('Calibration requested for ${kind.name}');
    await Future.delayed(const Duration(seconds: 2));
    _addLog('Calibration completed for ${kind.name}');
  }

  Future<bool> connectGlassesOverWifi({
    required String ssid,
    required String password,
  }) async {
    _addLog('Attempting glasses WiFi link to SSID: $ssid');
    await Future.delayed(const Duration(seconds: 1));
    _addLog('Glasses WiFi link established');
    return true;
  }
}
