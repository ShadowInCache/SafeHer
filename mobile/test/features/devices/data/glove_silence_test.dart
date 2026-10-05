import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safeher_app/features/devices/data/ble_providers.dart';
import 'package:safeher_app/features/devices/data/glove_link_providers.dart';
import 'package:safeher_app/features/devices/domain/glove_protocol.dart';
import 'package:safeher_app/features/devices/domain/models/ble_models.dart';

import '../../../test_utils/fake_ble_service.dart';

/// A subscribed glove is not a reporting one.
///
/// The firmware checked the IMU *after* starting BLE, so a glove with a dead
/// MPU-6500 advertised, paired, accepted a subscription, and then halted —
/// having sent nothing. `isListening` stayed true, and the Home screen said
/// "Glove live". The same silence follows a wedged inference loop, a flat
/// battery, or a glove left in `DATA_COLLECTION_MODE 1`.
///
/// The fused score was already honest: the aggregator drops a reading older
/// than ten seconds, so the signal went absent by itself. Only the UI claimed
/// protection that had stopped — which is the failure this codebase keeps
/// having to remove.
BleDiscoveredDevice _glove() => const BleDiscoveredDevice(
      id: 'glove-1',
      advertisedName: 'SafeHer-Glove',
      rssi: -50,
      isConnectable: true,
    );

void main() {
  late FakeBleService ble;
  late ProviderContainer container;

  setUp(() {
    // Short enough to test, long enough that one delayed notification does
    // not trip it. The production value is 15s.
    gloveSilenceTimeout = const Duration(milliseconds: 120);
    ble = FakeBleService();
    container = ProviderContainer(overrides: [bleServiceProvider.overrideWithValue(ble)]);
    addTearDown(container.dispose);
    addTearDown(() => gloveSilenceTimeout = const Duration(seconds: 15));
  });

  Future<void> connectGlove() async {
    container.read(gloveLinkProvider);
    await container.read(blePairingControllerProvider.notifier).connect(_glove());
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  test('a classification marks the glove as reporting', () async {
    ble.notifications[GloveBle.classificationCharacteristicUuid] = ['NORMAL,0.90'];

    await connectGlove();

    final state = container.read(gloveLinkProvider);
    expect(state.isListening, isTrue);
    expect(state.isReporting, isTrue);
    expect(state.isSilent, isFalse);
  });

  test('silence stops it counting as reporting, without disconnecting', () async {
    ble.notifications[GloveBle.classificationCharacteristicUuid] = ['NORMAL,0.90'];
    await connectGlove();
    expect(container.read(gloveLinkProvider).isReporting, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 200));

    final state = container.read(gloveLinkProvider);
    expect(state.isReporting, isFalse, reason: 'nothing arrived for two timeouts');
    expect(
      state.isListening,
      isTrue,
      reason: 'the subscription is still up — silence is not a disconnect',
    );
    expect(state.isSilent, isTrue);
  });

  test('a glove that never says anything is never reporting', () async {
    // The dead-sensor case exactly: it pairs, subscribes, and sends nothing.
    ble.notifications[GloveBle.classificationCharacteristicUuid] = [];

    await connectGlove();

    final state = container.read(gloveLinkProvider);
    expect(state.isListening, isTrue);
    expect(
      state.isReporting,
      isFalse,
      reason: 'the app must never report a silent glove as watching',
    );
  });

  test('the last reading is kept, so the UI does not blank', () async {
    // Silence means "stop claiming this is live", not "forget what it said".
    ble.notifications[GloveBle.classificationCharacteristicUuid] = ['SHAKING,0.80'];
    await connectGlove();

    await Future<void>.delayed(const Duration(milliseconds: 200));

    final state = container.read(gloveLinkProvider);
    expect(state.isReporting, isFalse);
    expect(state.classification?.label, 'SHAKING');
    expect(state.lastUpdate, isNotNull);
  });

  test('a disconnect clears reporting too', () async {
    ble.notifications[GloveBle.classificationCharacteristicUuid] = ['NORMAL,0.90'];
    await connectGlove();

    ble.dropConnection('glove-1');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final state = container.read(gloveLinkProvider);
    expect(state.isListening, isFalse);
    expect(state.isReporting, isFalse);
    expect(state.isSilent, isFalse, reason: 'disconnected is its own state, not silence');
  });
}
