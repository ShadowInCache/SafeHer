import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safeher_app/features/devices/data/ble_providers.dart';
import 'package:safeher_app/features/devices/data/device_providers.dart';
import 'package:safeher_app/features/devices/data/glove_autoconnect_providers.dart';
import 'package:safeher_app/features/devices/data/glove_link_providers.dart';
import 'package:safeher_app/features/devices/domain/device_repository.dart';
import 'package:safeher_app/features/devices/domain/models/ble_models.dart';
import 'package:safeher_app/features/devices/domain/models/ble_pairing_state.dart';
import 'package:safeher_app/features/devices/domain/models/device_detail.dart';

import '../../../test_utils/fake_ble_service.dart';

/// Nothing in this codebase previously watched [gloveLinkProvider] /
/// [GloveConnectionManager] / this provider at app startup — a closed and
/// reopened app (or a launch before the glove had power) never resumed
/// streaming until the user manually re-opened the pairing sheet. These
/// tests exist so that gap cannot come back quietly.
class _FakeDeviceRepository implements DeviceRepository {
  _FakeDeviceRepository(this.devices);

  List<DeviceDetail> devices;
  Object? error;

  @override
  Future<List<DeviceDetail>> getDevices() async {
    if (error != null) throw error!;
    return devices;
  }

  @override
  Future<void> unpairDevice(String id) async {}
}

const _glove = DeviceDetail(
  id: 'backend-glove-id',
  name: 'SafeHer-Glove',
  type: DeviceType.glove,
  isOnline: false,
  batteryPercent: 0.5,
  batteryHoursRemaining: 10,
  signalStrength: 0,
  firmwareVersion: 'v1',
  updateAvailable: false,
  sensors: SensorReading.unknown(),
);

const _ring = DeviceDetail(
  id: 'backend-ring-id',
  name: 'Smart Ring',
  type: DeviceType.ring,
  isOnline: false,
  batteryPercent: 0.5,
  batteryHoursRemaining: 10,
  signalStrength: 0,
  firmwareVersion: 'v1',
  updateAvailable: false,
  sensors: SensorReading.unknown(),
);

const _scannedGlove = BleDiscoveredDevice(
  id: 'AA:BB:CC:DD:EE:FF',
  advertisedName: 'SafeHer-Glove',
  rssi: -50,
  isConnectable: true,
);

void main() {
  late FakeBleService ble;
  late _FakeDeviceRepository repo;
  late ProviderContainer container;

  setUp(() {
    ble = FakeBleService();
    repo = _FakeDeviceRepository([_glove]);
    // Real durations would make this suite take minutes; shrink them for
    // every test, restored after each so other suites are unaffected.
    gloveAutoConnectScanWindow = const Duration(milliseconds: 200);
    gloveAutoConnectCooldown = const Duration(milliseconds: 50);
    container = ProviderContainer(
      overrides: [
        bleServiceProvider.overrideWithValue(ble),
        deviceRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() async => ble.dispose());
  });

  tearDown(() {
    gloveAutoConnectScanWindow = const Duration(seconds: 12);
    gloveAutoConnectCooldown = const Duration(seconds: 8);
  });

  test('does nothing when no glove is registered on the account', () async {
    repo.devices = [_ring];
    container.read(gloveAutoConnectProvider);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(ble.startScanCalls, 0);
    expect(ble.connectCalls, 0);
    expect(container.read(connectedGloveIdProvider), isNull);
  });

  test('does nothing when a glove is already connected this session', () async {
    container.read(connectedGloveIdProvider.notifier).state = 'already-connected-id';
    container.read(gloveAutoConnectProvider);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(ble.startScanCalls, 0);
  });

  test('finds and connects the registered glove, and GloveLink subscribes', () async {
    // Warm GloveLink first, exactly as main.dart does — otherwise its
    // ref.listen on BlePairingController is not attached yet when the
    // connect below happens, and it would miss the state change.
    container.read(gloveLinkProvider);
    container.read(gloveAutoConnectProvider);

    // Let the scan start, then deliver the matching advertisement.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    ble.emitDevices(const [_scannedGlove]);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(ble.startScanCalls, 1);
    expect(ble.connectCalls, 1);
    expect(container.read(connectedGloveIdProvider), _scannedGlove.id);
    expect(container.read(gloveLinkProvider).isListening, isTrue);
    // GloveLink subscribes via subscribeToCharacteristic, never the older
    // characteristicNotifications path — this is the dual-subscription
    // regression (two independent notify subscriptions on the same
    // characteristic) this whole investigation started from.
    expect(ble.characteristicNotificationsCalls, 0);
  });

  test('does not open a second scan or connection once connected', () async {
    container.read(gloveLinkProvider);
    container.read(gloveAutoConnectProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    ble.emitDevices(const [_scannedGlove]);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(ble.connectCalls, 1);

    // Rebuilding the provider (as a rebuild elsewhere in the app might)
    // must not start a second attempt now that a glove is connected.
    container.invalidate(gloveAutoConnectProvider);
    container.read(gloveAutoConnectProvider);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(ble.startScanCalls, 1);
    expect(ble.connectCalls, 1);
  });

  test('retries after a scan window with no match, not a tight loop', () async {
    container.read(gloveLinkProvider);
    container.read(gloveAutoConnectProvider);

    // First window: nothing found, must time out and retry rather than
    // hang or spin immediately.
    await Future<void>.delayed(gloveAutoConnectScanWindow + const Duration(milliseconds: 50));
    expect(ble.startScanCalls, 1);
    expect(ble.connectCalls, 0);

    // After the cooldown, a second window is opened, and this time the
    // glove is there.
    await Future<void>.delayed(gloveAutoConnectCooldown + const Duration(milliseconds: 20));
    ble.emitDevices(const [_scannedGlove]);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(ble.startScanCalls, 2);
    expect(ble.connectCalls, 1);
    expect(container.read(connectedGloveIdProvider), _scannedGlove.id);
  });

  test('a manual pairing that completes first wins; auto-connect backs off', () async {
    container.read(gloveLinkProvider);
    container.read(gloveAutoConnectProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Simulates the user manually pairing a *different* glove connection
    // while the auto-connect scan is still in flight.
    container.read(connectedGloveIdProvider.notifier).state = 'manually-paired-id';
    ble.emitDevices(const [_scannedGlove]);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    // The manual pairing's id must not be clobbered by the auto-connect
    // attempt racing behind it.
    expect(container.read(connectedGloveIdProvider), 'manually-paired-id');
    expect(ble.connectCalls, 0);
  });

  test('backs off when a manual connect is already mid-flight, not yet connected', () async {
    // Narrower than the "manual pairing that completes first wins" test
    // above: here the manual connect hasn't reached `connected` yet (so
    // connectedGloveIdProvider is still null) when auto-connect finds its
    // own match and is about to call connect() too. Without the busy-state
    // guard in glove_autoconnect_providers.dart, both would call
    // BlePairingController.connect() concurrently.
    final gate = Completer<void>();
    ble.connectGate = gate;
    container.read(gloveLinkProvider);
    final pairing = container.read(blePairingControllerProvider.notifier);
    pairing.selectDeviceType(DeviceType.glove);
    final manualConnect = pairing.connect(_scannedGlove);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(container.read(blePairingControllerProvider).stage, BlePairingStage.connecting);

    container.read(gloveAutoConnectProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    ble.emitDevices(const [_scannedGlove]);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(ble.connectCalls, 1, reason: 'auto-connect must back off, not race the manual connect');

    gate.complete();
    await manualConnect;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(container.read(blePairingControllerProvider).stage, BlePairingStage.connected);
    expect(container.read(connectedGloveIdProvider), _scannedGlove.id);
  });

  test('retries when the backend device list is temporarily unreachable', () async {
    repo.error = Exception('network down');
    container.read(gloveLinkProvider);
    container.read(gloveAutoConnectProvider);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(ble.startScanCalls, 0);

    repo.error = null;
    await Future<void>.delayed(gloveAutoConnectCooldown + const Duration(milliseconds: 30));
    ble.emitDevices(const [_scannedGlove]);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(ble.connectCalls, 1);
  });
}
