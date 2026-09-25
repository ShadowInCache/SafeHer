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
  final _notifications = <String, StreamController<String>>{};

  var startScanCalls = 0;
  var stopScanCalls = 0;
  var connectCalls = 0;
  var disconnectCalls = 0;
  var openSettingsCalls = 0;
  var characteristicNotificationsCalls = 0;

  // --- test controls -------------------------------------------------

  /// Pushes a new batch of discovered devices, as a live scan would.
  void emitDevices(List<BleDiscoveredDevice> devices) => _scanResults.add(devices);

  /// Simulates the scan timeout elapsing and the radio stopping.
  void completeScan() => _isScanning.add(false);

  void emitAdapterStatus(BleAdapterStatus status) => _adapter.add(status);

  /// Simulates the peripheral walking out of range or powering off.
  void dropConnection(String deviceId) =>
      _connectionFor(deviceId).add(BleConnectionStatus.disconnected);

  /// Pushes a raw notification value on [deviceId]'s subscription, as the
  /// real radio would after [characteristicNotifications] is listened to —
  /// e.g. `emitCharacteristicValue(id, 'CLASS=FALL,CONFIDENCE=0.9613')`.
  void emitCharacteristicValue(String deviceId, String value) =>
      _notificationsFor(deviceId).add(value);

  /// Simulates a subscribed characteristic erroring out (e.g. the link
  /// dropped mid-notification) without closing the stream outright.
  void emitCharacteristicError(String deviceId, Object error) =>
      _notificationsFor(deviceId).addError(error);

  Future<void> dispose() async {
    await _adapter.close();
    await _scanResults.close();
    await _isScanning.close();
    for (final controller in _connections.values) {
      await controller.close();
    }
    for (final controller in _notifications.values) {
      await controller.close();
    }
  }

  _ReplayController<BleConnectionStatus> _connectionFor(String deviceId) =>
      _connections.putIfAbsent(deviceId, () => _ReplayController(BleConnectionStatus.disconnected));

  StreamController<String> _notificationsFor(String deviceId) =>
      // Broadcast: mirrors the real FlutterBluePlusBleService, which
      // returns a fresh broadcast controller per call and so tolerates
      // being listened to more than once (e.g. a provider rebuild).
      _notifications.putIfAbsent(deviceId, StreamController<String>.broadcast);

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

  /// Notifications a test wants the fake glove to emit, keyed by
  /// characteristic UUID. Unset characteristics yield an empty stream, which
  /// is how firmware without the telemetry characteristic behaves.
  final Map<String, List<String>> notifications = {};

  /// Characteristics the fake should refuse, to exercise the "older firmware"
  /// path where a subscription throws rather than silently doing nothing.
  final Set<String> missingCharacteristics = {};

  /// When set, the *next* [subscribeToCharacteristic] call returns a stream
  /// whose cancellation never resolves -- reproducing, on the fake, the real
  /// hang this regression guards against: on real hardware,
  /// `FlutterBluePlusBleService`'s `subscribeToCharacteristic` cleanup awaits
  /// a GATT descriptor write the already-disconnected peripheral never
  /// answers, so `StreamSubscription.cancel()` never completed. GloveLink
  /// used to `await` that cancellation before starting a fresh subscription
  /// on reconnect, permanently blocking every future resubscription. Cleared
  /// after one use.
  bool hangNextCancellation = false;

  /// How many times [subscribeToCharacteristic] was called for each
  /// characteristic UUID -- lets a test assert "exactly one subscription per
  /// characteristic per connection" rather than assuming it.
  final subscribeCallsByCharacteristic = <String, int>{};

  @override
  Stream<String> subscribeToCharacteristic(
    String deviceId, {
    required String serviceUuid,
    required String characteristicUuid,
  }) {
    subscribeCallsByCharacteristic.update(characteristicUuid, (count) => count + 1, ifAbsent: () => 1);
    if (missingCharacteristics.contains(characteristicUuid)) {
      return Stream<String>.error(
        StateError('Service $serviceUuid has no characteristic $characteristicUuid'),
      );
    }
    final hang = hangNextCancellation;
    hangNextCancellation = false;
    late StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () {
        for (final message in notifications[characteristicUuid] ?? const <String>[]) {
          controller.add(message);
        }
      },
      // A real subscription stays open waiting for more notifications
      // rather than completing on its own -- matches that, and only ends
      // via cancellation.
      onCancel: hang ? () => Completer<void>().future : null,
    );
    return controller.stream;
  }

  @override
  Future<void> disconnect(String deviceId) async {
    disconnectCalls++;
    _connectionFor(deviceId).add(BleConnectionStatus.disconnected);
  }

  @override
  Stream<BleConnectionStatus> connectionState(String deviceId) => _connectionFor(deviceId).stream;

  @override
  Stream<String> characteristicNotifications(
    String deviceId, {
    required String serviceUuid,
    required String characteristicUuid,
  }) {
    characteristicNotificationsCalls++;
    return _notificationsFor(deviceId).stream;
  }
}
