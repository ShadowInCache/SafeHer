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
/// It is *not* a SafeHer sensor-telemetry pipe, and nothing built on it
/// should pretend otherwise. Per `ARCHITECTURE.md` and the ESP32 firmware
/// in `hardware/`, the real glove and glasses publish their sensor data to
/// the backend over **WiFi + MQTT directly** (`fastapi_app/mqtt_service.py`
/// subscribes to those topics). The phone is not a BLE bridge in that
/// path, and consequently **no SafeHer-specific GATT service or
/// characteristic UUID exists anywhere in this repo** — so there is
/// nothing to filter a scan by and no characteristic worth subscribing to.
/// What a successful pairing here buys you is a verified physical device
/// plus a backend registration record, not a live sensor stream.
///
/// Implementations must never fabricate a result: no invented devices, no
/// synthesised RSSI, no connection that reports success without the
/// platform confirming it.
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

  /// Our app's live connection state for [deviceId] — the stream that
  /// tells us the peripheral walked out of range or powered off.
  Stream<BleConnectionStatus> connectionState(String deviceId);
}
