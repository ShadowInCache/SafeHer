import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/data/ble_providers.dart';
import 'package:safeher_app/features/devices/data/motion_data_providers.dart';
import 'package:safeher_app/features/devices/domain/models/ble_models.dart';
import 'package:safeher_app/features/devices/domain/models/motion_data.dart';

import '../../../test_utils/fake_ble_service.dart';

void main() {
  group('GloveConnectionManager', () {
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

    test('does nothing while no glove is known', () async {
      final sub = container.listen(gloveConnectionManagerProvider, (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(fakeBle.connectCalls, 0);
    });

    test('does not retry while the known glove is connected', () async {
      const deviceId = 'glove-1';
      await fakeBle.connect(deviceId);
      container.read(connectedGloveIdProvider.notifier).state = deviceId;

      final sub = container.listen(gloveConnectionManagerProvider, (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // The one call above (the "initial connect" a real pairing flow would
      // have made) — nothing further from the manager while still linked.
      expect(fakeBle.connectCalls, 1);
    });

    test(
      'automatically reconnects a known glove after its BLE link drops, with no user action',
      () async {
        const deviceId = 'glove-1';
        await fakeBle.connect(deviceId);
        container.read(connectedGloveIdProvider.notifier).state = deviceId;

        final sub = container.listen(gloveConnectionManagerProvider, (_, _) {});
        addTearDown(sub.close);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(fakeBle.connectCalls, 1);

        // Simulates the ESP32's power being cut.
        fakeBle.dropConnection(deviceId);
        await Future<void>.delayed(const Duration(seconds: 4));

        // No pairing sheet, no tap — the manager called connect() again by
        // itself, and the real connectionState stream reports it back as
        // connected once that succeeds.
        expect(fakeBle.connectCalls, greaterThan(1));
        expect(
          container.read(gloveConnectionStateProvider(deviceId)).valueOrNull,
          BleConnectionStatus.connected,
        );
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'a fresh packet after automatic reconnect updates live data; the old reading is not replayed',
      () async {
        const deviceId = 'glove-1';
        await fakeBle.connect(deviceId);
        container.read(connectedGloveIdProvider.notifier).state = deviceId;

        final managerSub = container.listen(gloveConnectionManagerProvider, (_, _) {});
        addTearDown(managerSub.close);
        final liveSub = container.listen(liveMotionDataProvider(deviceId), (_, _) {});
        addTearDown(liveSub.close);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        fakeBle.emitCharacteristicValue(deviceId, 'CLASS=FALL,CONFIDENCE=0.9613');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(container.read(liveMotionDataProvider(deviceId)), const MotionData(classification: 'FALL', confidence: 0.9613));

        fakeBle.dropConnection(deviceId);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(container.read(liveMotionDataProvider(deviceId)), isNull);

        // Let the manager's automatic reconnect land.
        await Future<void>.delayed(const Duration(seconds: 4));
        expect(
          container.read(gloveConnectionStateProvider(deviceId)).valueOrNull,
          BleConnectionStatus.connected,
        );
        // Still no data: reconnecting alone must not resurrect the old
        // FALL reading.
        expect(container.read(liveMotionDataProvider(deviceId)), isNull);

        fakeBle.emitCharacteristicValue(deviceId, 'CLASS=PUSH,CONFIDENCE=0.8000');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          container.read(liveMotionDataProvider(deviceId)),
          const MotionData(classification: 'PUSH', confidence: 0.8000),
        );
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });
}
