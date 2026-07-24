import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../models/sensor_data_simplified.dart';

/// Service for managing Bluetooth Low Energy connections with smart wearables
/// Enhanced with reconnection logic and connection monitoring
class BLEService {
  static final BLEService _instance = BLEService._internal();
  factory BLEService() => _instance;
  BLEService._internal();

  // Connected devices
  BluetoothDevice? _gloveDevice;
  BluetoothDevice? _glassesDevice;

  // Stream controllers for device data
  final _gloveDataController = StreamController<MotionData>.broadcast();
  final _glassesConnectionController = StreamController<bool>.broadcast();
  final _gloveBatteryController = StreamController<int>.broadcast();
  final _glassesBatteryController = StreamController<int>.broadcast();
  final _connectionStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _gloveConnectionStateController = StreamController<bool>.broadcast();
  final _glassesConnectionStateController = StreamController<bool>.broadcast();

  // Getters for streams
  Stream<MotionData> get gloveDataStream => _gloveDataController.stream;
  Stream<bool> get glassesConnectionStream =>
      _glassesConnectionController.stream;
  Stream<int> get gloveBatteryStream => _gloveBatteryController.stream;
  Stream<int> get glassesBatteryStream => _glassesBatteryController.stream;
  Stream<Map<String, dynamic>> get connectionStatusStream =>
      _connectionStatusController.stream;
  Stream<bool> get gloveConnectionState =>
      _gloveConnectionStateController.stream;
  Stream<bool> get glassesConnectionState =>
      _glassesConnectionStateController.stream;

  // Connection state
  bool _isScanning = false;
  final List<BluetoothDevice> _discoveredDevices = [];

  // Reconnection settings
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 3);
  static const Duration _connectionTimeout = Duration(seconds: 15);

  // Reconnection state
  final Map<String, int> _reconnectAttempts = {'glove': 0, 'glasses': 0};
  final Map<String, Timer?> _reconnectTimers = {'glove': null, 'glasses': null};
  final Map<String, StreamSubscription?> _connectionSubscriptions = {
    'glove': null,
    'glasses': null,
  };

  /// Check if Bluetooth is available and enabled
  Future<bool> isBluetoothAvailable() async {
    try {
      if (await FlutterBluePlus.isSupported == false) {
        debugPrint("Bluetooth not supported by this device");
        return false;
      }

      // Check if Bluetooth is on
      var adapterState = await FlutterBluePlus.adapterState.first;
      return adapterState == BluetoothAdapterState.on;
    } catch (e) {
      debugPrint("Error checking Bluetooth availability: $e");
      return false;
    }
  }

  /// Start scanning for SafeHer devices (glove and glasses)
  Future<List<BluetoothDevice>> scanForDevices({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_isScanning) {
      debugPrint("Already scanning...");
      return _discoveredDevices;
    }

    _discoveredDevices.clear();
    _isScanning = true;

    try {
      // Start scanning
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: true,
      );

      // Listen for scan results
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          // Filter for SafeHer devices by name or service UUID
          if (result.device.platformName.contains('SafeHer') ||
              result.device.platformName.contains('Glove') ||
              result.device.platformName.contains('Glasses')) {
            if (!_discoveredDevices.contains(result.device)) {
              _discoveredDevices.add(result.device);
              debugPrint(
                "Found device: ${result.device.platformName} (${result.device.remoteId})",
              );
            }
          }
        }
      });

      // Wait for scan to complete
      await Future.delayed(timeout);
      await FlutterBluePlus.stopScan();
      _isScanning = false;

      return _discoveredDevices;
    } catch (e) {
      debugPrint("Error scanning for devices: $e");
      _isScanning = false;
      return [];
    }
  }

  /// Connect to a specific device (glove or glasses) with reconnection logic
  Future<bool> connectToDevice(
    BluetoothDevice device, {
    bool isGlove = true,
  }) async {
    String deviceType = isGlove ? 'glove' : 'glasses';

    try {
      debugPrint("🔌 Connecting to ${device.platformName} ($deviceType)...");

      // Reset reconnect attempts on new connection attempt
      _reconnectAttempts[deviceType] = 0;

      // Cancel any pending reconnect timer
      if (_reconnectTimers[deviceType] != null) {
        _reconnectTimers[deviceType]!.cancel();
        _reconnectTimers[deviceType] = null;
      }

      // Connect with timeout
      await device.connect(timeout: _connectionTimeout);

      // Discover services
      List<BluetoothService> services = await device.discoverServices();

      // Find SafeHer service
      BluetoothService? safeherService = services.firstWhere(
        (service) => service.uuid.toString() == AppConstants.bleServiceUuid,
        orElse: () => services.first,
      );

      if (isGlove) {
        _gloveDevice = device;
        _setupGloveListeners(safeherService);
        _gloveConnectionStateController.add(true);
        debugPrint("✅ Glove connected successfully");
      } else {
        _glassesDevice = device;
        _setupGlassesListeners(safeherService);
        _glassesConnectionStateController.add(true);
        debugPrint("✅ Glasses connected successfully");
      }

      // Monitor connection state with reconnection on drop
      _connectionSubscriptions[deviceType]?.cancel();
      _connectionSubscriptions[deviceType] = device.connectionState.listen((
        state,
      ) {
        bool isConnected = state == BluetoothConnectionState.connected;

        if (isGlove) {
          _gloveConnectionStateController.add(isConnected);
        } else {
          _glassesConnectionStateController.add(isConnected);
        }

        _connectionStatusController.add({
          'deviceType': deviceType,
          'isConnected': isConnected,
          'timestamp': DateTime.now(),
        });

        if (!isConnected) {
          debugPrint("⚠️ $deviceType device disconnected unexpectedly");
          _attemptReconnect(device, isGlove);
        } else {
          // Reset attempts on successful reconnection
          _reconnectAttempts[deviceType] = 0;
          debugPrint("✅ $deviceType device reconnected successfully");
        }
      });

      return true;
    } catch (e) {
      debugPrint("❌ Error connecting to $deviceType device: $e");
      _attemptReconnect(device, isGlove);
      return false;
    }
  }

  /// Attempt to reconnect to device with exponential backoff
  void _attemptReconnect(BluetoothDevice device, bool isGlove) {
    String deviceType = isGlove ? 'glove' : 'glasses';

    if (_reconnectAttempts[deviceType]! >= _maxReconnectAttempts) {
      debugPrint("❌ Max reconnect attempts for $deviceType reached");
      if (isGlove) {
        _gloveDevice = null;
        _gloveConnectionStateController.add(false);
      } else {
        _glassesDevice = null;
        _glassesConnectionStateController.add(false);
      }
      return;
    }

    _reconnectAttempts[deviceType] = _reconnectAttempts[deviceType]! + 1;
    int attempt = _reconnectAttempts[deviceType]!;

    // Exponential backoff: 3s, 6s, 12s, 24s, 48s
    Duration delay = _reconnectDelay * (1 << (attempt - 1));

    debugPrint(
      "⏳ Scheduling reconnect for $deviceType (attempt $attempt/$_maxReconnectAttempts) in ${delay.inSeconds}s",
    );

    // Cancel previous timer if exists
    _reconnectTimers[deviceType]?.cancel();

    // Schedule reconnect
    _reconnectTimers[deviceType] = Timer(delay, () async {
      debugPrint(
        "🔄 Attempting to reconnect to $deviceType (attempt $attempt)...",
      );
      await connectToDevice(device, isGlove: isGlove);
    });
  }

  /// Setup listeners for glove data (motion sensors, battery)
  void _setupGloveListeners(BluetoothService service) async {
    try {
      for (BluetoothCharacteristic characteristic in service.characteristics) {
        // Motion data characteristic
        if (characteristic.uuid.toString() ==
            AppConstants.bleCharacteristicUuid) {
          await characteristic.setNotifyValue(true);
          characteristic.lastValueStream.listen((value) {
            if (value.isNotEmpty) {
              // Parse motion data (accelerometer + gyroscope)
              MotionData motionData = _parseMotionData(value);
              _gloveDataController.add(motionData);
            }
          });
        }

        // Battery level characteristic (standard BLE UUID: 0x2A19)
        if (characteristic.uuid.toString().contains('2a19')) {
          await characteristic.setNotifyValue(true);
          characteristic.lastValueStream.listen((value) {
            if (value.isNotEmpty) {
              int batteryLevel = value[0];
              _gloveBatteryController.add(batteryLevel);
              debugPrint("Glove battery: $batteryLevel%");
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error setting up glove listeners: $e");
    }
  }

  /// Setup listeners for glasses data (connection, battery)
  void _setupGlassesListeners(BluetoothService service) async {
    try {
      for (BluetoothCharacteristic characteristic in service.characteristics) {
        // Battery level characteristic
        if (characteristic.uuid.toString().contains('2a19')) {
          await characteristic.setNotifyValue(true);
          characteristic.lastValueStream.listen((value) {
            if (value.isNotEmpty) {
              int batteryLevel = value[0];
              _glassesBatteryController.add(batteryLevel);
              debugPrint("Glasses battery: $batteryLevel%");
            }
          });
        }
      }

      _glassesConnectionController.add(true);
    } catch (e) {
      debugPrint("Error setting up glasses listeners: $e");
    }
  }

  /// Parse motion data from BLE bytes
  MotionData _parseMotionData(List<int> bytes) {
    try {
      // Expected format: 6 floats (3 accel + 3 gyro) = 24 bytes
      if (bytes.length < 24) {
        throw Exception("Invalid motion data length: ${bytes.length}");
      }

      // Convert bytes to doubles (simplified - real implementation would use ByteData)
      return MotionData(
        deviceId: _gloveDevice?.remoteId.toString() ?? 'unknown',
        timestamp: DateTime.now(),
        accelerometer: Accelerometer(
          x: _bytesToDouble(bytes.sublist(0, 4)),
          y: _bytesToDouble(bytes.sublist(4, 8)),
          z: _bytesToDouble(bytes.sublist(8, 12)),
        ),
        gyroscope: Gyroscope(
          x: _bytesToDouble(bytes.sublist(12, 16)),
          y: _bytesToDouble(bytes.sublist(16, 20)),
          z: _bytesToDouble(bytes.sublist(20, 24)),
        ),
      );
    } catch (e) {
      debugPrint("Error parsing motion data: $e");
      return MotionData(
        deviceId: 'error',
        timestamp: DateTime.now(),
        accelerometer: Accelerometer(x: 0, y: 0, z: 0),
        gyroscope: Gyroscope(x: 0, y: 0, z: 0),
      );
    }
  }

  /// Convert 4 bytes to double (simplified IEEE 754)
  double _bytesToDouble(List<int> bytes) {
    if (bytes.length != 4) return 0.0;
    // Simplified conversion - production should use ByteData.view.getFloat32
    int intValue =
        (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    return intValue / 1000.0; // Scale factor
  }

  /// Disconnect from a device
  Future<void> disconnectDevice({bool isGlove = true}) async {
    try {
      if (isGlove && _gloveDevice != null) {
        await _gloveDevice!.disconnect();
        _gloveDevice = null;
        debugPrint("Glove disconnected");
      } else if (!isGlove && _glassesDevice != null) {
        await _glassesDevice!.disconnect();
        _glassesDevice = null;
        debugPrint("Glasses disconnected");
      }
    } catch (e) {
      debugPrint("Error disconnecting device: $e");
    }
  }

  /// Disconnect all devices
  Future<void> disconnectAll() async {
    await disconnectDevice(isGlove: true);
    await disconnectDevice(isGlove: false);
  }

  /// Get current connection status
  Map<String, bool> getConnectionStatus() {
    return {
      'glove': _gloveDevice?.isConnected ?? false,
      'glasses': _glassesDevice?.isConnected ?? false,
    };
  }

  /// Read battery level for a specific device
  Future<int?> readBatteryLevel({bool isGlove = true}) async {
    try {
      BluetoothDevice? device = isGlove ? _gloveDevice : _glassesDevice;
      if (device == null || !device.isConnected) return null;

      List<BluetoothService> services = await device.discoverServices();
      for (BluetoothService service in services) {
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          if (characteristic.uuid.toString().contains('2a19')) {
            List<int> value = await characteristic.read();
            if (value.isNotEmpty) {
              return value[0];
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error reading battery level: $e");
    }
    return null;
  }

  /// Get signal strength (RSSI) for connected device
  Future<int?> getSignalStrength({bool isGlove = true}) async {
    try {
      BluetoothDevice? device = isGlove ? _gloveDevice : _glassesDevice;
      if (device == null || !device.isConnected) return null;

      return await device.readRssi();
    } catch (e) {
      debugPrint("Error reading RSSI: $e");
      return null;
    }
  }

  /// Send actuator command to smart glove (Shock/Buzzer/Vibration)
  /// Command types: 'shock', 'buzzer', 'vibration', 'led'
  Future<bool> sendActuatorCommand({
    required String command,
    int intensity = 255, // 0-255
    int duration = 500, // milliseconds
  }) async {
    try {
      if (_gloveDevice == null || !_gloveDevice!.isConnected) {
        debugPrint("Glove not connected, cannot send actuator command");
        return false;
      }

      List<BluetoothService> services = await _gloveDevice!.discoverServices();
      for (BluetoothService service in services) {
        // Look for actuator characteristic (custom UUID)
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          if (characteristic.uuid.toString().contains(
                'aa01',
              ) || // Custom actuator UUID
              characteristic.properties.write) {
            // Encode command: [command_type, intensity, duration_high, duration_low]
            int commandByte;
            switch (command.toLowerCase()) {
              case 'shock':
                commandByte = 0x01;
                break;
              case 'buzzer':
                commandByte = 0x02;
                break;
              case 'vibration':
                commandByte = 0x03;
                break;
              case 'led':
                commandByte = 0x04;
                break;
              default:
                debugPrint("Unknown command: $command");
                return false;
            }

            List<int> payload = [
              commandByte,
              intensity.clamp(0, 255),
              (duration >> 8) & 0xFF, // High byte
              duration & 0xFF, // Low byte
            ];

            await characteristic.write(payload, withoutResponse: false);
            debugPrint(
              "Actuator command sent: $command (intensity: $intensity, duration: $duration ms)",
            );
            return true;
          }
        }
      }

      debugPrint("Actuator characteristic not found");
      return false;
    } catch (e) {
      debugPrint("Error sending actuator command: $e");
      return false;
    }
  }

  /// Trigger immediate response based on threat level
  /// threatLevel: 0=Safe, 1=Low, 2=Medium, 3=High, 4=Critical
  Future<void> triggerImmediateResponse(int threatLevel) async {
    if (threatLevel < 3) return; // Only trigger for High/Critical threats

    try {
      if (threatLevel == 4) {
        // Critical: Shock + Buzzer + Vibration
        await sendActuatorCommand(
          command: 'shock',
          intensity: 255,
          duration: 1000,
        );
        await Future.delayed(const Duration(milliseconds: 100));
        await sendActuatorCommand(
          command: 'buzzer',
          intensity: 255,
          duration: 2000,
        );
        await sendActuatorCommand(
          command: 'vibration',
          intensity: 255,
          duration: 2000,
        );
        debugPrint("CRITICAL ALERT: All actuators triggered");
      } else if (threatLevel == 3) {
        // High: Buzzer + Vibration (no shock)
        await sendActuatorCommand(
          command: 'buzzer',
          intensity: 200,
          duration: 1500,
        );
        await sendActuatorCommand(
          command: 'vibration',
          intensity: 200,
          duration: 1500,
        );
        debugPrint("HIGH ALERT: Buzzer + Vibration triggered");
      }
    } catch (e) {
      debugPrint("Error triggering immediate response: $e");
    }
  }

  /// Dispose all resources
  void dispose() {
    _gloveDataController.close();
    _glassesConnectionController.close();
    _gloveBatteryController.close();
    _glassesBatteryController.close();
    _connectionStatusController.close();
  }
}
