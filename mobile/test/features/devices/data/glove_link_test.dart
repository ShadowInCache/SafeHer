import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safeher_app/features/devices/data/ble_providers.dart';
import 'package:safeher_app/features/devices/data/glove_link_providers.dart';
import 'package:safeher_app/features/devices/domain/glove_protocol.dart';
import 'package:safeher_app/features/devices/domain/models/ble_models.dart';
import 'package:safeher_app/features/devices/domain/models/ble_pairing_state.dart';
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

  group('concurrent connect protection', () {
    // GloveAutoConnect (glove_autoconnect_providers.dart) drives the same
    // BlePairingController in the background on every launch. If a manual
    // pairing-sheet connect and an auto-connect attempt ever land on
    // connect() at the same time, interleaved state emits could report
    // "connected" from a call whose GATT/subscription setup lost the race —
    // "Connected" on screen with no data ever arriving. This is that race,
    // reproduced directly against BlePairingController without going
    // through GloveAutoConnect at all.
    test('a second connect() call while one is in flight is ignored, not raced', () async {
      ble.notifications[GloveBle.classificationCharacteristicUuid] = ['FALL,0.93'];
      final gate = Completer<void>();
      ble.connectGate = gate;
      container.read(gloveLinkProvider);
      final notifier = container.read(blePairingControllerProvider.notifier);

      final first = notifier.connect(_glove());
      // First call is now mid-flight (blocked on the gate, stage ==
      // connecting). A second caller — the other of auto-connect / a manual
      // tap — attempting to connect right now must be turned away rather
      // than starting its own overlapping GATT attempt.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(container.read(blePairingControllerProvider).stage, BlePairingStage.connecting);
      await notifier.connect(_glove(id: 'glove-2'));

      expect(ble.connectCalls, 1, reason: 'the second call must not open its own GATT attempt');
      expect(
        container.read(blePairingControllerProvider).target?.id,
        'glove-1',
        reason: 'the in-flight attempt must not be clobbered by the ignored one',
      );

      gate.complete();
      await first;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(gloveLinkProvider);
      expect(container.read(blePairingControllerProvider).stage, BlePairingStage.connected);
      expect(state.isListening, isTrue);
      expect(state.classification?.label, 'FALL');
    });
  });

  group('reconnect after a hung cancellation', () {
    // The actual root cause of "reconnect shows Connected but no data":
    // FlutterBluePlusBleService's subscribeToCharacteristic cleanup awaits a
    // GATT descriptor write that an already-disconnected peripheral never
    // answers, so cancelling the old subscription never resolved. GloveLink
    // used to await that cancellation as the first thing _listen() did,
    // which meant every reconnect blocked forever before it could even
    // start rediscovering services. This proves the fix: _listen() must
    // proceed (and resubscribe) even when the previous subscription's
    // cancel() never completes.
    test("resubscribes on reconnect even if the old subscription's cancel() never resolves", () async {
      ble.notifications[GloveBle.classificationCharacteristicUuid] = ['NORMAL,0.99'];
      await connectGlove();
      expect(container.read(gloveLinkProvider).classification?.label, 'NORMAL');

      ble.hangNextCancellation = true;
      ble.notifications[GloveBle.classificationCharacteristicUuid] = ['FALL,0.88'];

      ble.dropConnection('glove-1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(gloveLinkProvider).isListening, isFalse,
          reason: 'state must clear on disconnect');

      await Future<void>.delayed(
        BlePairingController.reconnectBackoff + const Duration(milliseconds: 300),
      );

      final state = container.read(gloveLinkProvider);
      expect(state.isListening, isTrue,
          reason: 'reconnect must resubscribe even though the old cancel() is permanently stuck');
      expect(state.classification?.label, 'FALL');
    }, timeout: const Timeout(Duration(seconds: 10)));
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
