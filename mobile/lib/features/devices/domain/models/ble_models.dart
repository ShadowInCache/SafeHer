/// Plain-Dart models for the BLE pairing flow.
///
/// Nothing here imports `flutter_blue_plus` — the SDK's types stop at
/// `data/ble_service_flutter_blue_plus.dart`, which maps them into these.
/// That keeps `presentation/` (and every widget test) free of the radio.
library;

/// Power / authorization state of the phone's Bluetooth adapter.
///
/// Mirrors the states a real adapter can actually report. [unsupported]
/// means this hardware has no BLE at all; [unauthorized] means the OS
/// refused us access (iOS surfaces a denied Bluetooth permission this way).
enum BleAdapterStatus { unknown, unsupported, unauthorized, off, turningOn, on }

/// Outcome of asking the OS for the permissions a BLE scan needs.
enum BlePermissionStatus {
  granted,

  /// Denied this time; asking again may still show the system dialog.
  denied,

  /// Denied with "don't ask again" (or restricted by policy). The system
  /// dialog will never appear again — the only recovery is app settings.
  permanentlyDenied,
}

/// Whether *our app* currently holds a GATT connection to a peripheral.
enum BleConnectionStatus { disconnected, connected }

/// Coarse buckets for a real RSSI reading, used for the signal label and
/// bar count. Thresholds are the conventional BLE ones; the underlying
/// [BleDiscoveredDevice.rssi] is always the untouched radio value.
enum BleSignalQuality { weak, fair, strong }

/// A peripheral that genuinely showed up in a scan.
///
/// Every field comes from a real advertisement packet. When a peripheral
/// advertises no name, [advertisedName] is empty and [displayName] says
/// "Unknown Device" — a name is never invented for it.
class BleDiscoveredDevice {
  const BleDiscoveredDevice({
    required this.id,
    required this.advertisedName,
    required this.rssi,
    required this.isConnectable,
  });

  /// Platform device identifier: a MAC address on Android, a CoreBluetooth
  /// UUID on iOS. Stable enough to reconnect to within a session.
  final String id;

  /// The name from the advertisement (or the OS's cached name for the
  /// peripheral). Empty string when the peripheral advertised none.
  final String advertisedName;

  /// Real signal strength in dBm, straight from the scan result.
  final int rssi;

  /// Whether the advertisement flagged the peripheral as connectable.
  final bool isConnectable;

  bool get hasAdvertisedName => advertisedName.trim().isNotEmpty;

  String get displayName => hasAdvertisedName ? advertisedName.trim() : 'Unknown Device';

  /// Name sent to the backend on registration. Unnamed peripherals get
  /// their platform id appended so the stored record still points at a
  /// specific piece of hardware instead of a row of identical
  /// "Unknown Device" entries.
  String get registrationName => hasAdvertisedName ? advertisedName.trim() : 'Unknown Device ($id)';

  BleSignalQuality get signalQuality {
    if (rssi >= -65) return BleSignalQuality.strong;
    if (rssi >= -85) return BleSignalQuality.fair;
    return BleSignalQuality.weak;
  }

  /// 1–3 filled bars for [SaSignalBars], derived from [rssi].
  int get signalBars => switch (signalQuality) {
    BleSignalQuality.strong => 3,
    BleSignalQuality.fair => 2,
    BleSignalQuality.weak => 1,
  };

  String get signalLabel => switch (signalQuality) {
    BleSignalQuality.strong => 'Strong',
    BleSignalQuality.fair => 'Good',
    BleSignalQuality.weak => 'Weak',
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BleDiscoveredDevice &&
          other.id == id &&
          other.advertisedName == advertisedName &&
          other.rssi == rssi &&
          other.isConnectable == isConnectable;

  @override
  int get hashCode => Object.hash(id, advertisedName, rssi, isConnectable);
}

/// Proof that a connection was real: the GATT services the peripheral
/// actually exposed, discovered after [BleService.connect] returned.
class BleConnectionInfo {
  const BleConnectionInfo({required this.deviceId, required this.serviceUuids});

  final String deviceId;

  /// UUIDs returned by `discoverServices()`. May legitimately be empty —
  /// some peripherals expose no services beyond the mandatory GAP/GATT
  /// ones, and no SafeHer-specific service UUID exists to look for (see
  /// the note in `ble_service.dart`).
  final List<String> serviceUuids;

  int get serviceCount => serviceUuids.length;
}

/// A BLE operation that genuinely failed.
///
/// [message] carries the SDK's own description wherever the platform gave
/// us one, so the UI can show what actually went wrong instead of a
/// catch-all string.
class BleFailure implements Exception {
  const BleFailure(this.message, {this.code});

  final String message;

  /// Platform error code where the SDK supplied one.
  final int? code;

  @override
  String toString() => code == null ? message : '$message (code $code)';
}
