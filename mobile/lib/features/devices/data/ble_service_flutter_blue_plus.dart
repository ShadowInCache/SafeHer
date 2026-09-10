import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/ble_service.dart';
import '../domain/models/ble_models.dart';

/// The real [BleService], backed by `flutter_blue_plus`.
///
/// This is the only file in the app allowed to import `flutter_blue_plus`
/// or `permission_handler`; everything above it speaks the plain-Dart
/// models in `domain/models/ble_models.dart`.
///
/// Scans are unfiltered on purpose. There is no SafeHer GATT service UUID
/// to filter by — the shipping ESP32 firmware talks WiFi + MQTT straight
/// to the backend and does not advertise a BLE service (see
/// `domain/ble_service.dart` for the full note) — so filtering would only
/// hide real devices from the user.
class FlutterBluePlusBleService implements BleService {
  const FlutterBluePlusBleService();

  /// `dart:io`'s `Platform` is deliberately not used anywhere in this file.
  /// It throws `Unsupported operation: Platform._operatingSystem` on web,
  /// and because [canPromptToEnableBluetooth] is a plain getter read during
  /// the pairing sheet's build, that throw took down the whole screen with
  /// a red error page rather than surfacing as a handleable failure.
  /// `defaultTargetPlatform` answers the same question everywhere.
  static bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Web Bluetooth is a different shape of API from the native one: it has
  /// no free-running scan, only a browser-drawn chooser opened from a user
  /// gesture, so the scan-then-pick flow this app is built around cannot be
  /// driven from it. `permission_handler` has no web implementation either.
  /// Reporting "unsupported" up front is honest and lands the user on a
  /// screen that tells them what to do instead.
  @override
  Future<bool> isSupported() async {
    if (kIsWeb) return false;
    return FlutterBluePlus.isSupported;
  }

  @override
  BleAdapterStatus get adapterStatusNow => _mapAdapterState(FlutterBluePlus.adapterStateNow);

  @override
  Stream<BleAdapterStatus> get adapterStatus =>
      FlutterBluePlus.adapterState.map(_mapAdapterState).distinct();

  @override
  bool get canPromptToEnableBluetooth => _isAndroid;

  /// Android asks for `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` (API 31+) plus
  /// fine location — this app's `AndroidManifest.xml` declares
  /// `ACCESS_FINE_LOCATION` without `maxSdkVersion` and `BLUETOOTH_SCAN`
  /// without `neverForLocation`, i.e. the "with fine location" setup from
  /// the flutter_blue_plus README, so location is genuinely required for
  /// scan results to arrive. permission_handler no-ops the Android-12-only
  /// permissions on older API levels, so this is safe to request as-is.
  ///
  /// iOS has a single Bluetooth authorization, prompted by CoreBluetooth.
  @override
  Future<BlePermissionStatus> requestScanPermissions() async {
    final requested = _isAndroid
        ? <Permission>[Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse]
        : <Permission>[Permission.bluetooth];

    final results = await requested.request();
    return _worstStatus(results.values);
  }

  @override
  Future<bool> openPermissionSettings() => openAppSettings();

  @override
  Future<void> requestEnableBluetooth() async {
    if (!_isAndroid) {
      // iOS gives apps no way to power the radio on; CoreBluetooth only
      // lets us ask the user to do it from Settings or Control Centre.
      throw const BleFailure('Turn Bluetooth on in Settings to pair a device.');
    }
    try {
      await FlutterBluePlus.turnOn();
    } on FlutterBluePlusException catch (error) {
      throw _mapException(error, fallback: "Couldn't turn Bluetooth on.");
    }
  }

  @override
  Stream<List<BleDiscoveredDevice>> get scanResults =>
      FlutterBluePlus.scanResults.map((results) => results.map(_mapScanResult).toList());

  @override
  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  @override
  Future<void> startScan({Duration timeout = kBleScanTimeout}) async {
    try {
      await FlutterBluePlus.startScan(
        timeout: timeout,
        // Keep `lastSeen`/`rssi` fresh so the signal reading shown next to
        // a device reflects the latest advertisement rather than the first.
        continuousUpdates: true,
        // Drop devices that stop advertising, instead of leaving stale
        // entries in the list claiming to still be there.
        removeIfGone: const Duration(seconds: 8),
        androidUsesFineLocation: true,
      );
    } on FlutterBluePlusException catch (error) {
      throw _mapException(error, fallback: "Couldn't start scanning.");
    }
  }

  @override
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } on FlutterBluePlusException catch (error) {
      throw _mapException(error, fallback: "Couldn't stop scanning.");
    }
  }

  @override
  Future<BleConnectionInfo> connect(String deviceId, {Duration timeout = kBleConnectTimeout}) async {
    final device = BluetoothDevice.fromId(deviceId);
    try {
      await device.connect(timeout: timeout);
      // Service discovery is what proves the link is real: it round-trips
      // to the peripheral's GATT server rather than trusting a local flag.
      final services = await device.discoverServices();
      return BleConnectionInfo(
        deviceId: deviceId,
        serviceUuids: services.map((service) => service.uuid.str).toList(growable: false),
      );
    } on FlutterBluePlusException catch (error) {
      // Never leave a half-open connection behind after a failure.
      await _disconnectQuietly(device);
      throw _mapException(error, fallback: "Couldn't connect to this device.");
    }
  }

  /// Best-effort teardown on the failure path — if this throws too, the
  /// original connect error is the one worth surfacing.
  static Future<void> _disconnectQuietly(BluetoothDevice device) async {
    try {
      await device.disconnect();
    } on Exception {
      // Nothing to tear down: the link never came up, or is already gone.
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    try {
      await BluetoothDevice.fromId(deviceId).disconnect();
    } on FlutterBluePlusException catch (error) {
      throw _mapException(error, fallback: "Couldn't disconnect from this device.");
    }
  }

  @override
  Stream<BleConnectionStatus> connectionState(String deviceId) {
    return BluetoothDevice.fromId(deviceId).connectionState.map(
      (state) => state == BluetoothConnectionState.connected
          ? BleConnectionStatus.connected
          : BleConnectionStatus.disconnected,
    );
  }

  /// Looks up [serviceUuid]/[characteristicUuid] on an already-connected
  /// [deviceId], enables notifications, and forwards each value as a
  /// UTF-8-decoded string. `allowMalformed: true` on the decode because a
  /// bad byte belongs to [MotionData]'s parser to reject, not something
  /// that should crash this stream — see `domain/models/motion_data.dart`.
  ///
  /// Lazy: does nothing until the returned stream gets its first listener,
  /// and tears the subscription + notification flag down again when the
  /// last listener cancels, so an unwatched provider does not keep the
  /// peripheral's notify flag on forever.
  @override
  Stream<String> characteristicNotifications(
    String deviceId, {
    required String serviceUuid,
    required String characteristicUuid,
  }) {
    final device = BluetoothDevice.fromId(deviceId);
    late final StreamController<String> controller;
    StreamSubscription<List<int>>? valueSub;
    BluetoothCharacteristic? characteristic;

    Future<void> start() async {
      try {
        final services = await device.discoverServices();
        final service = services.firstWhere(
          (candidate) => candidate.uuid.str.toLowerCase() == serviceUuid.toLowerCase(),
          orElse: () => throw BleFailure('Service $serviceUuid not found on $deviceId.'),
        );
        characteristic = service.characteristics.firstWhere(
          (candidate) => candidate.uuid.str.toLowerCase() == characteristicUuid.toLowerCase(),
          orElse: () => throw BleFailure('Characteristic $characteristicUuid not found on $deviceId.'),
        );
        await characteristic!.setNotifyValue(true);
        valueSub = characteristic!.lastValueStream.listen(
          (bytes) {
            if (bytes.isEmpty) return;
            controller.add(utf8.decode(bytes, allowMalformed: true));
          },
          onError: controller.addError,
        );
      } on FlutterBluePlusException catch (error) {
        controller.addError(_mapException(error, fallback: "Couldn't subscribe to $characteristicUuid."));
      } on BleFailure catch (error) {
        controller.addError(error);
      }
    }

    controller = StreamController<String>.broadcast(
      onListen: () => unawaited(start()),
      onCancel: () async {
        await valueSub?.cancel();
        valueSub = null;
        try {
          await characteristic?.setNotifyValue(false);
        } on Exception {
          // Best-effort - the link may already be gone, which is fine: the
          // peripheral drops its subscriber list on disconnect anyway.
        }
      },
    );
    return controller.stream;
  }

  BleDiscoveredDevice _mapScanResult(ScanResult result) {
    // `advName` is what the peripheral put in this advertisement;
    // `platformName` is the OS's cached name for it. Both are real — we
    // just prefer the fresher one, and fall back to an empty name (shown
    // as "Unknown Device") rather than inventing anything.
    final advertised = result.advertisementData.advName;
    return BleDiscoveredDevice(
      id: result.device.remoteId.str,
      advertisedName: advertised.isNotEmpty ? advertised : result.device.platformName,
      rssi: result.rssi,
      isConnectable: result.advertisementData.connectable,
    );
  }

  static BleAdapterStatus _mapAdapterState(BluetoothAdapterState state) => switch (state) {
    BluetoothAdapterState.on => BleAdapterStatus.on,
    BluetoothAdapterState.turningOn => BleAdapterStatus.turningOn,
    BluetoothAdapterState.off || BluetoothAdapterState.turningOff => BleAdapterStatus.off,
    BluetoothAdapterState.unauthorized => BleAdapterStatus.unauthorized,
    BluetoothAdapterState.unavailable => BleAdapterStatus.unsupported,
    BluetoothAdapterState.unknown => BleAdapterStatus.unknown,
  };

  static BlePermissionStatus _worstStatus(Iterable<PermissionStatus> statuses) {
    if (statuses.any((s) => s.isPermanentlyDenied || s.isRestricted)) {
      return BlePermissionStatus.permanentlyDenied;
    }
    if (statuses.any((s) => !s.isGranted && !s.isLimited && !s.isProvisional)) {
      return BlePermissionStatus.denied;
    }
    return BlePermissionStatus.granted;
  }

  /// Keeps the platform's own error text, which is far more useful than a
  /// generic "connection failed" ("device is not connected", "GATT error
  /// 133", "ANDROID_SPECIFIC_ERROR", …).
  static BleFailure _mapException(FlutterBluePlusException error, {required String fallback}) {
    final description = error.description;
    return BleFailure(
      description != null && description.isNotEmpty ? description : fallback,
      code: error.code,
    );
  }
}
