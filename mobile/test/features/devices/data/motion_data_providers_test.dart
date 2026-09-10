import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/data/ble_providers.dart';
import 'package:safeher_app/features/devices/data/motion_data_providers.dart';
import 'package:safeher_app/features/devices/domain/models/motion_data.dart';

import '../../../test_utils/fake_ble_service.dart';

void main() {
  group('motionDataProvider', () {
    late FakeBleService fakeBle;
    late ProviderContainer container;

    setUp(() {
      fakeBle = FakeBleService();
      container = ProviderContainer(overrides: [bleServiceProvider.overrideWithValue(fakeBle)]);
    });

    tearDown(() async {
      container.dispose();
      await fakeBle.dispose();
    });

    test('subscribes via the exact glove service/characteristic UUIDs', () async {
      const deviceId = 'glove-1';
      final sub = container.listen(motionDataProvider(deviceId), (_, _) {});
      addTearDown(sub.close);

      // Let the async subscription set up.
      await Future<void>.delayed(Duration.zero);

      expect(fakeBle.characteristicNotificationsCalls, 1);
    });

    test('CLASS=FALL,CONFIDENCE=0.9613 arrives as motionClass=FALL, motionConfidence=0.9613', () async {
      const deviceId = 'glove-1';
      final emitted = <MotionData>[];
      final sub = container.listen(motionDataProvider(deviceId), (_, next) {
        next.whenData(emitted.add);
      });
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);

      fakeBle.emitCharacteristicValue(deviceId, 'CLASS=FALL,CONFIDENCE=0.9613');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, [const MotionData(classification: 'FALL', confidence: 0.9613)]);
    });

    test('a malformed packet is dropped, not surfaced as an error, and does not stop later valid ones', () async {
      const deviceId = 'glove-1';
      final emitted = <MotionData>[];
      final sub = container.listen(motionDataProvider(deviceId), (_, next) {
        next.whenData(emitted.add);
      });
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);

      fakeBle.emitCharacteristicValue(deviceId, 'CLASS=FALL,CONFIDENCE=abc'); // malformed
      fakeBle.emitCharacteristicValue(deviceId, 'CLASS=NORMAL,CONFIDENCE=0.9726'); // valid
      await Future<void>.delayed(Duration.zero);

      expect(emitted, [const MotionData(classification: 'NORMAL', confidence: 0.9726)]);
      expect(container.read(motionDataProvider(deviceId)).hasError, isFalse);
    });

    test('different device ids get independent subscriptions', () async {
      final subA = container.listen(motionDataProvider('glove-A'), (_, _) {});
      final subB = container.listen(motionDataProvider('glove-B'), (_, _) {});
      addTearDown(subA.close);
      addTearDown(subB.close);
      await Future<void>.delayed(Duration.zero);

      fakeBle.emitCharacteristicValue('glove-A', 'CLASS=PUSH,CONFIDENCE=0.8124');
      fakeBle.emitCharacteristicValue('glove-B', 'CLASS=PULL,CONFIDENCE=0.7341');
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(motionDataProvider('glove-A')).value,
        const MotionData(classification: 'PUSH', confidence: 0.8124),
      );
      expect(
        container.read(motionDataProvider('glove-B')).value,
        const MotionData(classification: 'PULL', confidence: 0.7341),
      );
    });
  });
}
