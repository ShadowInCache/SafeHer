import 'models/ble_models.dart';

/// How long a scan runs before the platform stops it automatically.
const kBleScanTimeout = Duration(seconds: 15);

/// How long a single connection attempt may take before it is treated as
/// a real failure. Deliberately shorter than flutter_blue_plus's own 35s
/// default — a safety app must not leave someone staring at a spinner.
const kBleConnectTimeout = Duration(seconds: 20);

/// The BLE radio, behind an interface.
///
/// ## What this is, and what it deliberately is not
///
/// This describes **real, generic BLE central-role work**: asking for the
/// OS permissions a scan needs, checking the adapter is actually powered
/// on, scanning for whatever peripherals are genuinely advertising nearby,
/// connecting to one, and running GATT service discovery to prove the
/// connection is real.
///
/// It is *not* a general SafeHer sensor-telemetry pipe, and nothing built
/// on it should pretend otherwise. Per `ARCHITECTURE.md` and the ESP32
/// firmware in `hardware/esp32_glove/`, that device publishes its sensor
/// data to the backend over **WiFi + MQTT directly**
/// (`fastapi_app/mqtt_service.py` subscribes to those topics) — the phone
/// is not a BLE bridge in that path, and no GATT service/characteristic
/// UUID exists for it. A successful pairing against *that* firmware buys
/// you a verified physical device plus a backend registration record, not
/// a live sensor stream — so scans stay unfiltered.
///
/// The separate `glove/firmware/SafeHer_Glove_Final/` ESP32-C3 firmware is
/// different: it runs the on-device V5 motion classifier and **does**
/// advertise a real GATT service (`4fafc201-1fb5-459e-8fcc-c5c9c331914b`)
/// with a result characteristic
/// (`beb5483e-36e1-4688-b7f5-ea07361b26a8`) that notifies
/// `CLASS=<name>,CONFIDENCE=<0.0-1.0>` once per inference window. Consuming
/// that is what [characteristicNotifications] and
/// `features/devices/data/motion_data_providers.dart` are for — see
/// `firmware/SafeHer_Glove_Final/SafeHer_Glove_Final.ino` for the source of
/// truth on that payload format.
///
/// Implementations must never fabricate a result: no invented devices, no
/// synthesised RSSI, no connection that reports success without the
/// platform confirming it, and no invented characteristic values either.
abstract class BleService {
  /// Whether this hardware supports BLE at all.
  Future<bool> isSupported();

  /// Last known adapter state, without waiting for the stream.
  BleAdapterStatus get adapterStatusNow;

  /// Live adapter power/authorization state.
  Stream<BleAdapterStatus> get adapterStatus;

  /// Requests every permission a scan needs on this platform.
  Future<BlePermissionStatus> requestScanPermissions();

  /// Opens the OS app-settings page so a permanently-denied permission can
  /// be re-granted. Returns whether the page was opened.
  Future<bool> openPermissionSettings();

  /// Whether this platform lets an app turn the adapter on programmatically.
  /// True on Android; false on iOS, where the user must do it themselves.
  bool get canPromptToEnableBluetooth;

  /// Asks the OS to enable Bluetooth. Throws [BleFailure] where the
  /// platform disallows it (iOS) or the user declines.
  Future<void> requestEnableBluetooth();

  /// Devices discovered so far in the current scan, re-emitted as each new
  /// advertisement arrives so the UI can fill in live.
  Stream<List<BleDiscoveredDevice>> get scanResults;

  /// Whether a scan is currently running.
  Stream<bool> get isScanning;

  /// Starts a real scan, stopping automatically after [timeout].
  Future<void> startScan({Duration timeout = kBleScanTimeout});

  Future<void> stopScan();

  /// Connects, then runs GATT service discovery. Throws [BleFailure] if
  /// either step fails (out of range, rejected, timed out).
  Future<BleConnectionInfo> connect(String deviceId, {Duration timeout = kBleConnectTimeout});

  Future<void> disconnect(String deviceId);

  /// Subscribes to notifications from one characteristic, as UTF-8 text.
  ///
  /// This is the piece that was missing. The service could scan, connect and
  /// prove a link was real, but had no way to *receive* anything -- so the
  /// glove notified its classifications into a socket nobody was listening
  /// on, and the app showed hardcoded zeros beside a device it had genuinely
  /// paired with.
  ///
  /// Returns a stream that closes when the link drops. Text rather than
  /// bytes because the glove speaks CSV (see `GloveBle`); a peripheral
  /// sending binary would need its own method rather than a lossy decode
  /// here.
  ///
  /// Throws if the service or characteristic is absent, so a glove running
  /// firmware without the telemetry characteristic fails loudly at the point
  /// of subscription rather than looking connected and silent.
  Stream<String> subscribeToCharacteristic(
    String deviceId, {
    required String serviceUuid,
    required String characteristicUuid,
  });

  /// Our app's live connection state for [deviceId] — the stream that
  /// tells us the peripheral walked out of range or powered off.
  Stream<BleConnectionStatus> connectionState(String deviceId);

  /// Live values notified by [characteristicUuid] on [deviceId]'s
  /// [serviceUuid], as UTF-8-decoded strings.
  ///
  /// [deviceId] must already be connected (see [connect]) — this method
  /// does not connect, reconnect, or otherwise manage connection lifecycle;
  /// that remains the caller's responsibility, same as [connectionState].
  /// Added for the SafeHer glove's motion-classification characteristic
  /// (see `features/devices/data/motion_data_providers.dart`), but takes
  /// the service/characteristic UUIDs as parameters rather than hardcoding
  /// them, so it stays usable for any future characteristic too.
  Stream<String> characteristicNotifications(
    String deviceId, {
    required String serviceUuid,
    required String characteristicUuid,
  });
}
