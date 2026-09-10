import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safeher_app/features/devices/data/ble_providers.dart';
import 'package:safeher_app/features/devices/data/glove_link_providers.dart';
import 'package:safeher_app/features/devices/domain/glove_protocol.dart';
import 'package:safeher_app/features/devices/domain/models/ble_models.dart';
import 'package:safeher_app/shared/models/threat_level.dart';

import '../../../test_utils/fake_ble_service.dart';

/// The glove paired, the model ran on the ESP32, and nothing in the app ever
/// subscribed to a characteristic -- so the classifications went into a
/// socket with no listener. These tests exist so that cannot happen quietly
/// again: if the subscription stops being made, they fail.
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

  Future<void> connectGlove({BleDiscoveredDevice? device}) async {
    // Warm the link provider so its listener is attached before the pairing
    // state moves -- exactly as the app does by watching it on screen.
    container.read(gloveLinkProvider);
    await container
        .read(blePairingControllerProvider.notifier)
        .connect(device ?? _glove());
    // Let the subscription streams deliver.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  group('subscribing', () {
    test('starts out with nothing and is not listening', () {
      final state = container.read(gloveLinkProvider);

      expect(state.isListening, isFalse);
      expect(state.classification, isNull);
      expect(state.telemetry, isNull);
      expect(state.hasData, isFalse);
    });

    test('receives a classification once the glove connects', () async {
      ble.notifications[GloveBle.classificationCharacteristicUuid] = ['FALL,0.93'];

      await connectGlove();

      final state = container.read(gloveLinkProvider);
      expect(state.isListening, isTrue, reason: 'the app must actually subscribe');
      expect(state.classification?.label, 'FALL');
      expect(state.classification?.confidence, closeTo(0.93, 1e-9));
      expect(state.classification?.threatLevel, ThreatLevel.danger);
    });

    test('receives telemetry, including heart rate', () async {
      ble.notifications[GloveBle.telemetryCharacteristicUuid] = ['1.02,4.3,78,86'];

      await connectGlove();

      final t = container.read(gloveLinkProvider).telemetry!;
      expect(t.accelG, closeTo(1.02, 1e-9));
      expect(t.gyroDps, closeTo(4.3, 1e-9));
      expect(t.heartRateBpm, closeTo(78, 1e-9));
      expect(t.batteryPercent, closeTo(86, 1e-9));
    });

    test('keeps only the most recent reading of each kind', () async {
      ble.notifications[GloveBle.classificationCharacteristicUuid] = [
        'NORMAL,0.10',
        'JERK,0.40',
        'FALL,0.95',
      ];

      await connectGlove();

      expect(container.read(gloveLinkProvider).classification?.label, 'FALL');
    });
  });

  group('firmware that predates telemetry', () {
    test('still delivers classifications, and says telemetry is unsupported', () async {
      // Additive firmware change: a glove without the telemetry
      // characteristic must keep working rather than failing to connect.
      ble.missingCharacteristics.add(GloveBle.telemetryCharacteristicUuid);
      ble.notifications[GloveBle.classificationCharacteristicUuid] = ['PUSH,0.7'];

      await connectGlove();

      final state = container.read(gloveLinkProvider);
      expect(state.classification?.label, 'PUSH');
      expect(state.isListening, isTrue);
      expect(state.telemetry, isNull);
      expect(state.telemetryUnsupported, isTrue,
          reason: 'the UI should be able to explain the missing numbers');
    });
  });

  group('robustness', () {
    test('a malformed notification does not clear the last good reading', () async {
      // A truncated BLE packet is a lost reading, not evidence that the
      // previous one was wrong.
      ble.notifications[GloveBle.classificationCharacteristicUuid] = [
        'FALL,0.93',
        'FAL',
        '',
      ];

      await connectGlove();

      expect(container.read(gloveLinkProvider).classification?.label, 'FALL');
    });

    test('a device that is not a SafeHer glove is not subscribed to', () async {
      ble.notifications[GloveBle.classificationCharacteristicUuid] = ['FALL,0.99'];

      await connectGlove(device: _glove(id: 'other-1', name: 'Someone Else Fitness Band'));

      final state = container.read(gloveLinkProvider);
      expect(state.isListening, isFalse);
      expect(state.classification, isNull,
          reason: "a stranger's peripheral must not feed the threat display");
    });

    test('a glove that cannot provide classifications reports no data', () async {
      ble.missingCharacteristics.add(GloveBle.classificationCharacteristicUuid);

      await connectGlove();

      final state = container.read(gloveLinkProvider);
      expect(state.isListening, isFalse);
      expect(state.hasData, isFalse);
    });
  });
}
