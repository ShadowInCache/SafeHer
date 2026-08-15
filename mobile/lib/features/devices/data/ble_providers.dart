import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/network_providers.dart';
import '../domain/ble_service.dart';
import '../domain/device_registration_repository.dart';
import '../domain/models/ble_models.dart';
import '../domain/models/ble_pairing_state.dart';
import '../domain/models/device_detail.dart';
import 'ble_service_flutter_blue_plus.dart';
import 'device_providers.dart';
import 'device_registration_repository_mock.dart';
import 'device_registration_repository_remote.dart';

part 'ble_providers.g.dart';

/// The real radio. Widget tests override this with a fake [BleService] —
/// there is no mock variant behind `AppConfig.useMockApi`, because a fake
/// scan result is exactly the thing this feature exists to stop shipping.
@Riverpod(keepAlive: true)
BleService bleService(Ref ref) => const FlutterBluePlusBleService();

@Riverpod(keepAlive: true)
DeviceRegistrationRepository deviceRegistrationRepository(Ref ref) {
  if (AppConfig.useMockApi) return DeviceRegistrationRepositoryMock();
  return DeviceRegistrationRepositoryRemote(apiClient: ref.watch(apiClientProvider));
}

/// Drives the BLE pairing sheet: permissions → adapter state → live scan →
/// connect + service discovery → backend registration, plus bounded
/// automatic reconnection when a real link drops.
///
/// Auto-disposed with the sheet. On dispose it cancels its subscriptions
/// and stops any running scan, but deliberately does **not** drop an
/// established GATT link — tearing down a connection the user just made
/// because they swiped a sheet away would be the wrong call. Owning that
/// connection for the rest of the session is a separate concern that
/// belongs to a device-connection manager, which does not exist yet.
@riverpod
class BlePairingController extends _$BlePairingController {
  /// Reconnect attempts allowed per disconnection episode. Bounded on
  /// purpose: an unbounded retry loop drains the battery of the phone a
  /// user may be relying on in an emergency.
  static const maxReconnectAttempts = 3;

  /// Delay before each automatic reconnect attempt.
  static const reconnectBackoff = Duration(seconds: 2);

  StreamSubscription<List<BleDiscoveredDevice>>? _scanResultsSub;
  StreamSubscription<bool>? _isScanningSub;
  StreamSubscription<BleAdapterStatus>? _adapterSub;
  StreamSubscription<BleConnectionStatus>? _connectionSub;
  Timer? _reconnectTimer;
  bool _disposed = false;

  /// Bumped every time the scan subscriptions are dropped, so late events
  /// from a previous scan can be told apart from the current one's.
  int _scanGeneration = 0;

  /// Cached so [_teardown] can stop a running scan without touching [ref],
  /// which is no longer readable once disposal has begun.
  BleService? _cachedService;

  @override
  BlePairingState build() {
    ref.onDispose(_teardown);
    final service = ref.read(bleServiceProvider);
    _cachedService = service;
    return BlePairingState(canPromptToEnableBluetooth: service.canPromptToEnableBluetooth);
  }

  BleService get _service => _cachedService ?? (_cachedService = ref.read(bleServiceProvider))!;

  /// Riverpod throws if state is written after dispose, and every write
  /// here happens in a callback that may outlive the sheet.
  void _emit(BlePairingState next) {
    if (_disposed) return;
    state = next;
  }

  void _teardown() {
    _disposed = true;
    _reconnectTimer?.cancel();
    unawaited(_scanResultsSub?.cancel());
    unawaited(_isScanningSub?.cancel());
    unawaited(_adapterSub?.cancel());
    unawaited(_connectionSub?.cancel());
    unawaited(_stopScanQuietly());
  }

  Future<void> _stopScanQuietly() async {
    try {
      await _service.stopScan();
    } on BleFailure {
      // Nothing was scanning, or the adapter went away — either way there
      // is no scan left to stop and nothing useful to tell the user.
    }
  }

  /// Drops the scan subscriptions without awaiting their cancellation.
  ///
  /// `StreamSubscription.cancel()` completes only when the producing stream
  /// decides to let go, so awaiting it here would hand a third-party SDK
  /// the power to wedge the whole pairing flow. [_scanGeneration] makes
  /// that safe: any event still in flight from a cancelled subscription is
  /// stamped with an older generation and ignored.
  void _cancelScanSubscriptions() {
    _scanGeneration++;
    unawaited(_scanResultsSub?.cancel());
    unawaited(_isScanningSub?.cancel());
    _scanResultsSub = null;
    _isScanningSub = null;
  }

  /// Full entry point: checks support, permissions and adapter power
  /// before a single advertisement is requested.
  ///
  /// Every step is inside the guard below, not just the `startScan()` call.
  /// The support check, the permission request and the adapter probe all
  /// cross a platform channel, and any of them can throw something that is
  /// not a [BleFailure] — a `MissingPluginException` on a platform with no
  /// BLE implementation being the obvious one. Those used to escape this
  /// method entirely, leaving the sheet spinning on `scanning` with nothing
  /// on screen to explain it: "connecting devices doesn't work", with no
  /// error to go on.
  Future<void> startScan() async {
    try {
      await _startScan();
    } on BleFailure catch (failure) {
      _emit(state.copyWith(stage: BlePairingStage.scanFailed, errorMessage: failure.message));
    } catch (error) {
      _emit(
        state.copyWith(
          stage: BlePairingStage.scanFailed,
          errorMessage: _describeUnexpected(error),
        ),
      );
    }
  }

  /// Bluetooth failures are mostly platform-channel noise. Translate the
  /// one case a user can act on, and keep the raw text for the rest rather
  /// than hiding it behind "something went wrong" — a developer reading a
  /// bug report needs it, and it is not sensitive.
  String _describeUnexpected(Object error) {
    if (error is MissingPluginException) {
      return 'Bluetooth pairing is not available on this platform. '
          'Run SafeHer on an Android or iOS device to pair a wearable.';
    }
    return 'Bluetooth failed to start: $error';
  }

  Future<void> _startScan() async {
    _reconnectTimer?.cancel();
    _cancelScanSubscriptions();
    await _stopScanQuietly();

    _emit(
      state.copyWith(
        stage: BlePairingStage.scanning,
        devices: const [],
        clearTarget: true,
        clearError: true,
        clearRegisteredDevice: true,
        serviceCount: 0,
        reconnectAttempt: 0,
      ),
    );

    final service = _service;
    if (!await service.isSupported()) {
      _emit(
        state.copyWith(
          stage: BlePairingStage.unsupported,
          errorMessage: "This phone doesn't support Bluetooth Low Energy.",
        ),
      );
      return;
    }

    final permission = await service.requestScanPermissions();
    if (permission != BlePermissionStatus.granted) {
      _emit(
        state.copyWith(
          stage: BlePairingStage.permissionRequired,
          permissionPermanentlyDenied: permission == BlePermissionStatus.permanentlyDenied,
        ),
      );
      return;
    }

    final adapter = await _resolveAdapterStatus(service);
    switch (adapter) {
      case BleAdapterStatus.unsupported:
        _emit(
          state.copyWith(
            stage: BlePairingStage.unsupported,
            errorMessage: "This phone doesn't support Bluetooth Low Energy.",
          ),
        );
        return;
      case BleAdapterStatus.unauthorized:
        // iOS reports a denied Bluetooth permission as an unauthorized
        // adapter; the system prompt is already spent, so settings is the
        // only way back.
        _emit(state.copyWith(stage: BlePairingStage.permissionRequired, permissionPermanentlyDenied: true));
        return;
      case BleAdapterStatus.off:
        _emit(state.copyWith(stage: BlePairingStage.bluetoothDisabled));
        return;
      case BleAdapterStatus.on:
      case BleAdapterStatus.turningOn:
      case BleAdapterStatus.unknown:
        break;
    }

    _listenToAdapter(service);

    await service.startScan();

    // Subscribed after startScan so the first `isScanning` value we see is
    // `true` rather than the pre-scan `false`.
    final generation = _scanGeneration;
    _scanResultsSub = service.scanResults.listen((devices) => _onScanResults(generation, devices));
    _isScanningSub = service.isScanning.listen((scanning) => _onScanningChanged(generation, scanning));
  }

  void _onScanResults(int generation, List<BleDiscoveredDevice> devices) {
    if (generation != _scanGeneration) return;
    if (state.stage != BlePairingStage.scanning) return;
    final sorted = [...devices]..sort((a, b) => b.rssi.compareTo(a.rssi));
    _emit(state.copyWith(devices: sorted));
  }

  void _onScanningChanged(int generation, bool scanning) {
    if (generation != _scanGeneration) return;
    // The radio stopping on its own means the scan timeout elapsed.
    if (!scanning && state.stage == BlePairingStage.scanning) {
      _emit(state.copyWith(stage: BlePairingStage.scanComplete));
    }
  }

  void _listenToAdapter(BleService service) {
    unawaited(_adapterSub?.cancel());
    _adapterSub = service.adapterStatus.listen((status) {
      if (status == BleAdapterStatus.off && state.stage != BlePairingStage.idle) {
        _reconnectTimer?.cancel();
        _cancelScanSubscriptions();
        _emit(state.copyWith(stage: BlePairingStage.bluetoothDisabled, devices: const []));
      }
    });
  }

  /// The adapter state can legitimately be [BleAdapterStatus.unknown] for
  /// a moment after the plugin initialises; wait briefly for a real value
  /// rather than declaring Bluetooth broken.
  Future<BleAdapterStatus> _resolveAdapterStatus(BleService service) async {
    final now = service.adapterStatusNow;
    if (now != BleAdapterStatus.unknown) return now;
    try {
      return await service.adapterStatus
          .firstWhere((status) => status != BleAdapterStatus.unknown)
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      return BleAdapterStatus.unknown;
    } on StateError {
      return BleAdapterStatus.unknown;
    }
  }

  Future<void> stopScan() async {
    _cancelScanSubscriptions();
    await _stopScanQuietly();
    if (state.stage == BlePairingStage.scanning) {
      _emit(state.copyWith(stage: BlePairingStage.scanComplete));
    }
  }

  /// Android only — iOS throws, and the message tells the user to do it
  /// themselves, because CoreBluetooth genuinely offers no other option.
  Future<void> enableBluetooth() async {
    try {
      await _service.requestEnableBluetooth();
    } on BleFailure catch (failure) {
      _emit(state.copyWith(errorMessage: failure.message));
      return;
    }
    await startScan();
  }

  Future<void> openAppSettings() => _service.openPermissionSettings();

  void selectDeviceType(DeviceType type) => _emit(state.copyWith(selectedType: type));

  Future<void> connect(BleDiscoveredDevice device) async {
    _cancelScanSubscriptions();
    await _stopScanQuietly();
    _emit(
      state.copyWith(
        stage: BlePairingStage.connecting,
        target: device,
        clearError: true,
        clearRegisteredDevice: true,
        serviceCount: 0,
        reconnectAttempt: 0,
      ),
    );
    await _attemptConnect(device);
  }

  /// Retries the last failed connection against the same device.
  Future<void> retryConnection() async {
    final target = state.target;
    if (target == null) return;
    _emit(state.copyWith(stage: BlePairingStage.connecting, clearError: true, reconnectAttempt: 0));
    await _attemptConnect(target);
  }

  Future<void> _attemptConnect(BleDiscoveredDevice device) async {
    try {
      final info = await _service.connect(device.id);
      _emit(
        state.copyWith(
          stage: BlePairingStage.connected,
          serviceCount: info.serviceCount,
          clearError: true,
          reconnectAttempt: 0,
        ),
      );
      _listenToConnectionState(device);
    } on BleFailure catch (failure) {
      _emit(state.copyWith(stage: BlePairingStage.connectionFailed, errorMessage: failure.message));
    } catch (error) {
      // Same reasoning as startScan: a platform-channel throw that isn't a
      // BleFailure used to escape and strand the sheet on `connecting`
      // forever, with no way for the user to tell a broken link from a hung
      // app.
      _emit(
        state.copyWith(
          stage: BlePairingStage.connectionFailed,
          errorMessage: _describeUnexpected(error),
        ),
      );
    }
  }

  void _listenToConnectionState(BleDiscoveredDevice device) {
    unawaited(_connectionSub?.cancel());
    _connectionSub = _service.connectionState(device.id).listen((status) {
      if (status == BleConnectionStatus.disconnected && state.holdsConnection) {
        _onUnexpectedDisconnect(device);
      }
    });
  }

  void _onUnexpectedDisconnect(BleDiscoveredDevice device) {
    _emit(state.copyWith(stage: BlePairingStage.disconnected));
    _scheduleReconnect(device);
  }

  void _scheduleReconnect(BleDiscoveredDevice device) {
    if (_disposed) return;
    if (state.reconnectAttempt >= maxReconnectAttempts) {
      _emit(
        state.copyWith(
          stage: BlePairingStage.connectionFailed,
          errorMessage:
              'Lost connection to ${device.displayName} and could not reconnect '
              'after $maxReconnectAttempts attempts.',
        ),
      );
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectBackoff, () => unawaited(_reconnect(device)));
  }

  Future<void> _reconnect(BleDiscoveredDevice device) async {
    if (_disposed) return;
    _emit(state.copyWith(stage: BlePairingStage.reconnecting, reconnectAttempt: state.reconnectAttempt + 1));
    try {
      final info = await _service.connect(device.id);
      _emit(
        state.copyWith(
          stage: BlePairingStage.connected,
          serviceCount: info.serviceCount,
          clearError: true,
          reconnectAttempt: 0,
        ),
      );
      _listenToConnectionState(device);
    } on BleFailure catch (failure) {
      _emit(state.copyWith(stage: BlePairingStage.disconnected, errorMessage: failure.message));
      _scheduleReconnect(device);
    }
  }

  /// Registers the connected peripheral with the backend using its real
  /// advertised name and the wearable type the user picked.
  Future<void> registerConnectedDevice() async {
    final target = state.target;
    if (target == null || state.stage != BlePairingStage.connected) return;

    _emit(state.copyWith(stage: BlePairingStage.registering, clearError: true));
    try {
      final registered = await ref
          .read(deviceRegistrationRepositoryProvider)
          .registerDevice(deviceName: target.registrationName, deviceType: state.selectedType);
      _emit(state.copyWith(stage: BlePairingStage.registered, registeredDevice: registered));
      // `devicesProvider` (device_repository_remote.dart) now reads from
      // the same `fastapi_app` backend this registration just wrote to —
      // invalidating it here is what actually surfaces the newly paired
      // device in the list, rather than leaving it stuck until the next
      // unrelated refresh.
      ref.invalidate(devicesProvider);
    } catch (error) {
      // Back to `connected`, which is still true: the radio link survived,
      // only the backend write failed, so retrying costs no reconnection.
      _emit(state.copyWith(stage: BlePairingStage.connected, errorMessage: error.toString()));
    }
  }

  /// Manual unpair. Really disconnects the GATT link.
  ///
  /// Local only: `fastapi_app/routers/devices.py` has no unpair, delete or
  /// deactivate route, so there is nothing legitimate to call server-side.
  /// The backend record stays until that endpoint exists.
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    unawaited(_connectionSub?.cancel());
    _connectionSub = null;

    final target = state.target;
    String? failureMessage;
    if (target != null) {
      try {
        await _service.disconnect(target.id);
      } on BleFailure catch (failure) {
        failureMessage = failure.message;
      }
    }

    _emit(
      BlePairingState(
        stage: BlePairingStage.idle,
        selectedType: state.selectedType,
        canPromptToEnableBluetooth: state.canPromptToEnableBluetooth,
        errorMessage: failureMessage,
      ),
    );
  }
}
