import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safeher_app/features/devices/data/ble_providers.dart';
import 'package:safeher_app/features/devices/data/glove_link_providers.dart';
import 'package:safeher_app/features/devices/data/motion_data_providers.dart';
import 'package:safeher_app/features/devices/domain/glove_protocol.dart';
import 'package:safeher_app/features/devices/domain/models/ble_models.dart';

import '../../../test_utils/fake_ble_service.dart';

/// [motionRiskScoreProvider] and [liveMotionClassificationProvider] derive
/// from [gloveLinkProvider]'s state rather than opening their own BLE
/// subscription -- an earlier version subscribed to the classification
/// characteristic independently, which raced [GloveLink]'s own subscription
/// to the same characteristic and, in practice, silently lost that race on
/// real hardware (classification never arrived; telemetry, a different
/// characteristic, did). These tests exist so a regression back to a second
/// subscription is caught here rather than on a physical glove.
BleDiscoveredDevice _glove({String id = 'glove-1', String name = 'SafeHer-Glove'}) =>
    BleDiscoveredDevice(id: id, advertisedName: name, rssi: -50, isConnectable: true);

void main() {
  late FakeBleService ble;
  late ProviderContainer container;

  setUp(() {
    ble = FakeBleService();
    container = ProviderContainer(overrides: [bleServiceProvider.overrideWithValue(ble)]);
    addTearDown(container.dispose);
  });

  Future<void> connectGlove() async {
    container.read(gloveLinkProvider);
    await container.read(blePairingControllerProvider.notifier).connect(_glove());
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  group('motionRiskScoreProvider', () {
    test('is null before any classification has arrived', () {
      expect(container.read(motionRiskScoreProvider('glove-1')), isNull);
    });

    test('FALL at 0.9613 confidence scores 96.13', () async {
      ble.notifications[GloveBle.classificationCharacteristicUuid] = ['FALL,0.9613'];
      await connectGlove();

      expect(container.read(motionRiskScoreProvider('glove-1')), closeTo(96.13, 0.01));
    });

    test('NORMAL is always 0 regardless of confidence', () async {
      ble.notifications[GloveBle.classificationCharacteristicUuid] = ['NORMAL,0.99'];
      await connectGlove();

      expect(container.read(motionRiskScoreProvider('glove-1')), 0.0);
    });

    test('does not open a second subscription to the classification characteristic', () async {
      ble.notifications[GloveBle.classificationCharacteristicUuid] = ['SUDDEN_MOVEMENT,0.81'];
      await connectGlove();

      // Just reading the derived providers must not trigger any BLE call of
      // their own -- GloveLink's subscription (already exercised by
      // connectGlove) is the only one.
      container.read(motionRiskScoreProvider('glove-1'));
      container.read(liveMotionClassificationProvider('glove-1'));

      expect(ble.characteristicNotificationsCalls, 0);
    });
  });

  group('liveMotionClassificationProvider', () {
    test('is null before any classification has arrived', () {
      expect(container.read(liveMotionClassificationProvider('glove-1')), isNull);
    });

    test('reports the raw label from the glove', () async {
      ble.notifications[GloveBle.classificationCharacteristicUuid] = ['SUDDEN_MOVEMENT,0.81'];
      await connectGlove();

      expect(container.read(liveMotionClassificationProvider('glove-1')), 'SUDDEN_MOVEMENT');
    });
  });
}
