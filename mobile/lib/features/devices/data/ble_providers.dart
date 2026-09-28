import 'dart:async';

import 'package:flutter/foundation.dart';
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
import '../domain/models/registered_device.dart';
import 'ble_service_flutter_blue_plus.dart';
import 'device_providers.dart';
import 'device_registration_repository_mock.dart';
import 'device_registration_repository_remote.dart';

part 'ble_providers.g.dart';

void _bleLog(String message) {
  if (kDebugMode) debugPrint('[BLE] $message');
}

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

/// The BLE device id (`BleDiscoveredDevice.id`) of the glove
/// [BlePairingController] currently holds its one GATT link to, or `null`
/// when there is none.
///
/// The registered-device record shown elsewhere in the app (`DeviceDetail`,
/// from the backend) carries no BLE address — only this in-memory link
/// knows it, and only for as long as [BlePairingController] keeps it open
/// (which, per its own doc comment, can outlive the pairing sheet). This
/// provider exists solely so a screen with a backend `DeviceDetail` but no
/// BLE id — e.g. the device list's expandable card — can still find the
/// live [motionDataProvider] stream for the glove already connected here.
/// It does not open, own, or duplicate a connection; it only names the one
/// [BlePairingController] already has.
final connectedGloveIdProvider = StateProvider<String?>((ref) => null);

/// The real, live GATT connection state for [deviceId] — straight from
/// [BleService.connectionState], not inferred from whether a motion packet
/// has arrived recently.
///
/// `characteristicNotifications` goes quiet (no error, no "done") when the
/// peripheral disconnects — see its doc comment — so it cannot answer "is
/// the glove still there right now" on its own. This can. Consumers that
/// need to know whether the last [MotionData] value is still current
/// should watch this, not just check whether one exists.
final gloveConnectionStateProvider = StreamProvider.autoDispose.family<BleConnectionStatus, String>((
  ref,
  deviceId,
) {
  return ref.watch(bleServiceProvider).connectionState(deviceId);
});

/// Drives the BLE pairing sheet: permissions → adapter state → live scan →
/// connect + service discovery → backend registration, plus automatic
/// reconnection when a real link drops (including a power cycle — the ESP32
/// losing power and coming back).
///
/// Auto-disposed *with the sheet*, in the Riverpod sense of "nothing left
/// watching or listening" — closing the sheet after a successful pairing
/// does not actually tear this down, because [GloveLink] (`keepAlive`,
/// watched from `main.dart`) holds a `ref.listen` on this provider for the
/// whole app session. That is deliberate and load-bearing: it is what lets
/// the reconnect loop below outlive the sheet at all.
///
/// This controller used to be one of *two* independent things reconnecting
/// a dropped glove — a `GloveConnectionManager` provider called
/// `BleService.connect` directly on its own timer, racing this controller's
/// own reconnect for the same device. Whichever one happened to win left
/// the *other* signal wrong: `GloveConnectionManager` never touched
/// [BlePairingState.stage], so when it won the race the radio came back up
/// but [GloveLink] — which resubscribes on *this* controller reaching
/// [BlePairingStage.connected], not on the raw GATT state — never saw a
/// transition to react to. That reproduced as "shows Connected, no data"
/// after every power cycle, deterministically, because the tighter-interval
/// `GloveConnectionManager` almost always won. `GloveConnectionManager` is
/// gone now; this is the one and only place a reconnect happens.
@riverpod
class BlePairingController extends _$BlePairingController {
  /// Delay before each automatic reconnect attempt. Fixed, not growing —
  /// this now has to cover an ordinary power cycle (the ESP32 off for
  /// anywhere from seconds to minutes), so it retries for as long as the
  /// device stays disconnected rather than giving up after a handful of
  /// tries; a plain BLE connect attempt every couple of seconds is cheap
  /// enough on the phone's battery for a safety wearable to justify not
  /// stopping on its own. [disconnect] (the user's own unpair action) is
  /// still the only thing that stops it for good.
  static const reconnectBackoff = Duration(seconds: 2);

  StreamSubscription<List<BleDiscoveredDevice>>? _scanResultsSub;
  StreamSubscription<bool>? _isScanningSub;
  StreamSubscription<BleAdapterStatus>? _adapterSub;
  StreamSubscription<BleConnectionStatus>? _connectionSub;
  Timer? _reconnectTimer;
  bool _disposed = false;

  /// True from the moment [connect]/[retryConnection] starts a GATT attempt
  /// until it resolves. [GloveAutoConnect] runs in the background on every
  /// launch and drives this same controller; without this guard, a manual
  /// pairing-sheet tap landing while an auto-connect attempt is mid-flight
  /// (or the reverse) would let two `_attemptConnect` calls interleave their
  /// `_emit`s on the shared [state] — the controller ends up reporting
  /// `connected` from whichever call finished last while the actual GATT
  /// link / notification setup belongs to a discarded call, exactly the
  /// "shows Connected, streams nothing" bug this guard exists to rule out.
  bool _connecting = false;

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

  /// "No BLE here" means two very different things. On a phone it is a
  /// hardware fact the user can do nothing about; in a browser it means
  /// they are simply running SafeHer somewhere it cannot pair, and the
  /// answer is to open it on their phone. Telling a Chrome user their
  /// "phone doesn't support Bluetooth" would be both wrong and a dead end.
  static String get _unsupportedMessage => kIsWeb
      ? 'Pairing a wearable needs the SafeHer app on your phone — a browser '
            'cannot talk to Bluetooth devices this way. Everything else here '
            'works in the browser.'
      : "This phone doesn't support Bluetooth Low Energy.";

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
          errorMessage: _unsupportedMessage,
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
            errorMessage: _unsupportedMessage,
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
    _bleLog('scan started');

    // Subscribed after startScan so the first `isScanning` value we see is
    // `true` rather than the pre-scan `false`.
    final generation = _scanGeneration;
    _seenDeviceIds.clear();
    _scanResultsSub = service.scanResults.listen((devices) => _onScanResults(generation, devices));
    _isScanningSub = service.isScanning.listen((scanning) => _onScanningChanged(generation, scanning));
  }

  /// Logged once per device id per scan, not once per re-emission — the
  /// scan stream re-emits the whole growing list on every advertisement,
  /// including ones already seen.
  final Set<String> _seenDeviceIds = {};

  void _onScanResults(int generation, List<BleDiscoveredDevice> devices) {
    if (generation != _scanGeneration) return;
    if (state.stage != BlePairingStage.scanning) return;
    for (final device in devices) {
      if (_seenDeviceIds.add(device.id)) {
        _bleLog('device discovered (${device.displayName}, ${device.id})');
      }
    }
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

  void selectDeviceType(DeviceType type) {
    _emit(state.copyWith(selectedType: type));
    _syncConnectedGloveId();
  }

  /// Keeps [connectedGloveIdProvider] in sync with whether the device this
  /// controller currently holds the connection for is actually a glove.
  ///
  /// This controller is shared by every wearable type — ring, glasses,
  /// glove, pendant — and the radio has no way to know which one a
  /// peripheral is; [selectDeviceType] is how the user tells it, and it
  /// can be tapped (and change the answer) *after* connecting. Setting
  /// [connectedGloveIdProvider] unconditionally on every successful
  /// connect, regardless of [BlePairingState.selectedType], would wrongly
  /// point the glove-only motion pipeline — GloveLink, the device
  /// screen's Motion Risk Score — at
  /// whatever non-glove peripheral the user most recently paired.
  void _syncConnectedGloveId() {
    final target = state.target;
    if (target == null) return;
    if (state.selectedType == DeviceType.glove) {
      ref.read(connectedGloveIdProvider.notifier).state = target.id;
    } else if (ref.read(connectedGloveIdProvider) == target.id) {
      ref.read(connectedGloveIdProvider.notifier).state = null;
    }
  }

  Future<void> connect(BleDiscoveredDevice device) async {
    if (_connecting) {
      _bleLog('connect ignored: already connecting (${device.id})');
      return;
    }
    _connecting = true;
    try {
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
    } finally {
      _connecting = false;
    }
  }

  /// Retries the last failed connection against the same device.
  Future<void> retryConnection() async {
    if (_connecting) return;
    final target = state.target;
    if (target == null) return;
    _connecting = true;
    try {
      _emit(state.copyWith(stage: BlePairingStage.connecting, clearError: true, reconnectAttempt: 0));
      await _attemptConnect(target);
    } finally {
      _connecting = false;
    }
  }

  Future<void> _attemptConnect(BleDiscoveredDevice device) async {
    _bleLog('connecting (${device.displayName}, ${device.id})');
    try {
      final info = await _service.connect(device.id);
      _bleLog('connected (${device.id})');
      _bleLog('services discovered (${info.serviceCount})');
      _emit(
        state.copyWith(
          stage: BlePairingStage.connected,
          serviceCount: info.serviceCount,
          clearError: true,
          reconnectAttempt: 0,
        ),
      );
      _syncConnectedGloveId();
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
    _bleLog('disconnected (${device.id})');
    _emit(state.copyWith(stage: BlePairingStage.disconnected));
    _scheduleReconnect(device);
  }

  /// Schedules the next reconnect attempt. Never gives up on its own — see
  /// the class doc for why: this is the only reconnect path left, and a
  /// power cycle can legitimately take far longer than a handful of quick
  /// retries. [disconnect] (an explicit user unpair) is the only thing that
  /// stops this loop.
  void _scheduleReconnect(BleDiscoveredDevice device) {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectBackoff, () => unawaited(_reconnect(device)));
  }

  Future<void> _reconnect(BleDiscoveredDevice device) async {
    if (_disposed) return;
    _bleLog('reconnect attempt ${state.reconnectAttempt + 1} (${device.id})');
    _emit(state.copyWith(stage: BlePairingStage.reconnecting, reconnectAttempt: state.reconnectAttempt + 1));
    try {
      final info = await _service.connect(device.id);
      _bleLog('reconnect successful (${device.id})');
      _emit(
        state.copyWith(
          stage: BlePairingStage.connected,
          serviceCount: info.serviceCount,
          clearError: true,
          reconnectAttempt: 0,
        ),
      );
      _syncConnectedGloveId();
      _listenToConnectionState(device);
    } on BleFailure catch (failure) {
      _emit(state.copyWith(stage: BlePairingStage.disconnected, errorMessage: failure.message));
      _scheduleReconnect(device);
    } catch (error) {
      // Same reasoning as _attemptConnect: a non-BleFailure platform-channel
      // throw must not silently kill the retry loop — this is now the only
      // thing standing between a power cycle and a glove that never comes
      // back without the user manually reopening the pairing sheet.
      _emit(state.copyWith(stage: BlePairingStage.disconnected, errorMessage: _describeUnexpected(error)));
      _scheduleReconnect(device);
    }
  }

  /// Registers the connected peripheral with the backend using its real
  /// advertised name and the wearable type the user picked.
  ///
  /// Reuses an already-registered device of the same name and type instead
  /// of registering a new one, so reconnecting the SAME physical wearable
  /// (e.g. after its power was cycled) does not create a duplicate backend
  /// record and a second card in the device list. The backend has no BLE
  /// address to match on (`RegisteredDevice` carries none — see its doc
  /// comment), so the glove's fixed advertised name is the best identity
  /// signal available; two distinct physical units that happened to
  /// advertise the identical name would be conflated by this, but that is
  /// not a case this firmware/app pairing produces today.
  Future<void> registerConnectedDevice() async {
    final target = state.target;
    if (target == null || state.stage != BlePairingStage.connected) return;

    _emit(state.copyWith(stage: BlePairingStage.registering, clearError: true));
    try {
      var existingDevices = const <DeviceDetail>[];
      try {
        existingDevices = await ref.read(devicesProvider.future);
      } catch (_) {
        // Can't tell whether this glove is already registered — fall back
        // to registering it rather than blocking pairing on a transient
        // list-fetch failure. Worst case: one avoidable duplicate.
      }
      DeviceDetail? alreadyRegistered;
      for (final device in existingDevices) {
        if (device.name == target.registrationName && device.type == state.selectedType) {
          alreadyRegistered = device;
          break;
        }
      }

      final RegisteredDevice registered;
      if (alreadyRegistered != null) {
        registered = RegisteredDevice(
          id: alreadyRegistered.id,
          deviceName: alreadyRegistered.name,
          deviceType: alreadyRegistered.type,
          isActive: true,
        );
      } else {
        registered = await ref
            .read(deviceRegistrationRepositoryProvider)
            .registerDevice(deviceName: target.registrationName, deviceType: state.selectedType);
      }
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
      if (ref.read(connectedGloveIdProvider) == target.id) {
        ref.read(connectedGloveIdProvider.notifier).state = null;
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
