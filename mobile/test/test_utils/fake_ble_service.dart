import 'dart:async';

import 'package:safeher_app/features/devices/domain/ble_service.dart';
import 'package:safeher_app/features/devices/domain/models/ble_models.dart';

/// Broadcast stream that replays its latest value to every new listener —
/// the same behaviour flutter_blue_plus gives `scanResults`, `isScanning`,
/// `adapterState` and `connectionState`, which the controller relies on.
///
/// Each listener gets its own single-subscription controller, mirroring
/// flutter_blue_plus's `newStreamWithInitialValue` transformer. An `async*`
/// generator would be the obvious shortcut, but a subscription to one only
/// finishes cancelling when the generator is resumed — so `cancel()` can
/// hang forever, which is not how the real SDK behaves.
class _ReplayController<T> {
  _ReplayController(this._latest);

  T _latest;
  final _controller = StreamController<T>.broadcast();

  Stream<T> get stream {
    late StreamController<T> perListener;
    StreamSubscription<T>? upstream;
    perListener = StreamController<T>(
      onListen: () {
        perListener.add(_latest);
        upstream = _controller.stream.listen(
          perListener.add,
          onError: perListener.addError,
          onDone: perListener.close,
        );
      },
      onCancel: () async => upstream?.cancel(),
    );
    return perListener.stream;
  }

  void add(T value) {
    _latest = value;
    // flutter_test leaves the previous test's widget tree mounted until the
    // next `pumpWidget`, so a controller teardown can land after this fake
    // was disposed. Dropping the event beats throwing in an unrelated test.
    if (_controller.isClosed) return;
    _controller.add(value);
  }

  Future<void> close() => _controller.close();
}

/// Stand-in for the real radio in widget tests.
///
/// There is no Bluetooth hardware in a `flutter test` environment — a real
/// [BleService] would block on platform channels that never answer — so
/// tests drive this instead and push the exact scan results, connection
/// outcomes and disconnections they want to assert on. It is a test double
/// only; nothing in `lib/` may use it.
class FakeBleService implements BleService {
  FakeBleService({
    this.supported = true,
    this.permission = BlePermissionStatus.granted,
    BleAdapterStatus adapter = BleAdapterStatus.on,
    this.canPromptToEnableBluetooth = true,
    this.connectFailure,
    this.serviceUuids = const ['00001800-0000-1000-8000-00805f9b34fb', '0000180f-0000-1000-8000-00805f9b34fb'],
    this.enableBluetoothFailure,
  }) : _adapter = _ReplayController<BleAdapterStatus>(adapter);

  final bool supported;

  /// When set, [isSupported] throws this — the platform-channel failure
  /// mode on a target with no BLE implementation compiled in.
  Object? supportCheckError;

  BlePermissionStatus permission;

  @override
  final bool canPromptToEnableBluetooth;

  /// When set, [connect] throws this instead of succeeding.
  ///
  /// Deliberately `Object?` rather than `BleFailure?`: the interesting
  /// regression is the *non*-BleFailure throw (a MissingPluginException,
  /// say) that used to escape the controller and strand the pairing sheet.
  Object? connectFailure;

  /// When set, [connect] blocks on it — lets a test hold the flow in its
  /// "Connecting" state for as long as it needs.
  Completer<void>? connectGate;

  /// When set, [requestEnableBluetooth] throws this.
  final BleFailure? enableBluetoothFailure;

  /// Services reported by a successful [connect].
  final List<String> serviceUuids;

  final _ReplayController<BleAdapterStatus> _adapter;
  final _scanResults = _ReplayController<List<BleDiscoveredDevice>>(const []);
  final _isScanning = _ReplayController<bool>(false);
  final _connections = <String, _ReplayController<BleConnectionStatus>>{};

  var startScanCalls = 0;
  var stopScanCalls = 0;
  var connectCalls = 0;
  var disconnectCalls = 0;
  var openSettingsCalls = 0;

  // --- test controls -------------------------------------------------

  /// Pushes a new batch of discovered devices, as a live scan would.
  void emitDevices(List<BleDiscoveredDevice> devices) => _scanResults.add(devices);

  /// Simulates the scan timeout elapsing and the radio stopping.
  void completeScan() => _isScanning.add(false);

  void emitAdapterStatus(BleAdapterStatus status) => _adapter.add(status);

  /// Simulates the peripheral walking out of range or powering off.
  void dropConnection(String deviceId) =>
      _connectionFor(deviceId).add(BleConnectionStatus.disconnected);

  Future<void> dispose() async {
    await _adapter.close();
    await _scanResults.close();
    await _isScanning.close();
    for (final controller in _connections.values) {
      await controller.close();
    }
  }

  _ReplayController<BleConnectionStatus> _connectionFor(String deviceId) =>
      _connections.putIfAbsent(deviceId, () => _ReplayController(BleConnectionStatus.disconnected));

  // --- BleService ----------------------------------------------------

  @override
  Future<bool> isSupported() async {
    final error = supportCheckError;
    if (error != null) throw error;
    return supported;
  }

  @override
  BleAdapterStatus get adapterStatusNow => _adapter._latest;

  @override
  Stream<BleAdapterStatus> get adapterStatus => _adapter.stream;

  @override
  Future<BlePermissionStatus> requestScanPermissions() async => permission;

  @override
  Future<bool> openPermissionSettings() async {
    openSettingsCalls++;
    return true;
  }

  @override
  Future<void> requestEnableBluetooth() async {
    if (enableBluetoothFailure != null) throw enableBluetoothFailure!;
    _adapter.add(BleAdapterStatus.on);
  }

  @override
  Stream<List<BleDiscoveredDevice>> get scanResults => _scanResults.stream;

  @override
  Stream<bool> get isScanning => _isScanning.stream;

  @override
  Future<void> startScan({Duration timeout = kBleScanTimeout}) async {
    startScanCalls++;
    _scanResults.add(const []);
    _isScanning.add(true);
  }

  @override
  Future<void> stopScan() async {
    stopScanCalls++;
    _isScanning.add(false);
  }

  @override
  Future<BleConnectionInfo> connect(String deviceId, {Duration timeout = kBleConnectTimeout}) async {
    connectCalls++;
    final gate = connectGate;
    if (gate != null) await gate.future;
    final failure = connectFailure;
    if (failure != null) throw failure;
    _connectionFor(deviceId).add(BleConnectionStatus.connected);
    return BleConnectionInfo(deviceId: deviceId, serviceUuids: serviceUuids);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    disconnectCalls++;
    _connectionFor(deviceId).add(BleConnectionStatus.disconnected);
  }

  @override
  Stream<BleConnectionStatus> connectionState(String deviceId) => _connectionFor(deviceId).stream;
}
