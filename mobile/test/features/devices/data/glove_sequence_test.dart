import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safeher_app/features/devices/data/ble_providers.dart';
import 'package:safeher_app/features/devices/data/glove_link_providers.dart';
import 'package:safeher_app/features/devices/domain/glove_protocol.dart';
import 'package:safeher_app/features/devices/domain/models/ble_models.dart';

import '../../../test_utils/fake_ble_service.dart';

/// Lost classifications used to be invisible.
///
/// GATT notifications are *unacknowledged*: the glove calls `notify()` and
/// never learns whether the phone received it. With no counter in the payload
/// a dropped classification looked exactly like a quiet half-second — and
/// since a fall produces two to four windows while the alarm rule needs two of
/// them, losing two of three silently costs an alarm.
///
/// The firmware's inference counter makes the loss *detectable*. It does not
/// make it recoverable: nothing is retained or re-sent. Knowing is still worth
/// a great deal more than not knowing.
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
    ble = FakeBleService();
    container = ProviderContainer(overrides: [bleServiceProvider.overrideWithValue(ble)]);
    addTearDown(container.dispose);
  });

  Future<void> connectWith(List<String> notifications) async {
    ble.notifications[GloveBle.classificationCharacteristicUuid] = notifications;
    container.read(gloveLinkProvider);
    await container.read(blePairingControllerProvider.notifier).connect(_glove());
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }

  group('parsing the optional counter', () {
    test('a third field is read as the sequence', () {
      final parsed = GloveClassification.tryParse('FALL,0.93,42')!;
      expect(parsed.label, 'FALL');
      expect(parsed.confidence, closeTo(0.93, 1e-9));
      expect(parsed.sequence, 42);
    });

    test('firmware without a counter still parses', () {
      // The whole point of landing this before the firmware change.
      final parsed = GloveClassification.tryParse('FALL,0.93')!;
      expect(parsed.label, 'FALL');
      expect(parsed.sequence, isNull);
    });

    test('the keyed format keeps working, with or without a counter', () {
      // `SafeHer_Glove_Final` sends CLASS=/CONFIDENCE=.
      final bare = GloveClassification.tryParse('CLASS=FALL,CONFIDENCE=0.9300')!;
      expect(bare.label, 'FALL');
      expect(bare.sequence, isNull);

      final keyed =
          GloveClassification.tryParse('CLASS=FALL,CONFIDENCE=0.9300,SEQ=7')!;
      expect(keyed.sequence, 7);
    });

    test('a garbled counter never costs us the classification', () {
      // A real FALL with an unreadable sequence is still a real FALL.
      final parsed = GloveClassification.tryParse('FALL,0.93,notanumber')!;
      expect(parsed.label, 'FALL');
      expect(parsed.sequence, isNull);
    });
  });

  group('counting what was lost', () {
    test('a clean run loses nothing', () async {
      await connectWith(['NORMAL,0.9,1', 'NORMAL,0.9,2', 'FALL,0.8,3']);

      final state = container.read(gloveLinkProvider);
      expect(state.droppedNotifications, 0);
      expect(state.lossIsMeasurable, isTrue);
    });

    test('a gap in the counter is counted', () async {
      // 1, then 5: three never arrived.
      await connectWith(['NORMAL,0.9,1', 'FALL,0.8,5']);

      expect(container.read(gloveLinkProvider).droppedNotifications, 3);
    });

    test('gaps accumulate across a connection', () async {
      await connectWith(['NORMAL,0.9,1', 'NORMAL,0.9,3', 'FALL,0.8,6']);

      // one lost before #3, two before #6
      expect(container.read(gloveLinkProvider).droppedNotifications, 3);
    });

    test('a glove that sends no counter reports nothing measurable', () async {
      // Zero here must not be read as a clean link — it is an unknown one.
      await connectWith(['NORMAL,0.9', 'FALL,0.8']);

      final state = container.read(gloveLinkProvider);
      expect(state.droppedNotifications, 0);
      expect(
        state.lossIsMeasurable,
        isFalse,
        reason: 'this firmware cannot tell us about loss, which is not the '
            'same as telling us there was none',
      );
    });

    test('a reboot restarts the count instead of inventing a huge gap', () async {
      // The counter restarts at zero on reset. Treated naively that is four
      // billion lost packets.
      await connectWith(['NORMAL,0.9,900', 'NORMAL,0.9,1', 'FALL,0.8,2']);

      expect(container.read(gloveLinkProvider).droppedNotifications, 0);
    });

    test('a repeated counter is not a gap', () async {
      await connectWith(['NORMAL,0.9,4', 'NORMAL,0.9,4']);

      expect(container.read(gloveLinkProvider).droppedNotifications, 0);
    });

    test('reconnecting clears the count', () async {
      await connectWith(['NORMAL,0.9,1', 'FALL,0.8,5']);
      expect(container.read(gloveLinkProvider).droppedNotifications, 3);

      ble.dropConnection('glove-1');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        container.read(gloveLinkProvider).droppedNotifications,
        0,
        reason: 'the firmware counter restarts on reboot, so a total carried '
            'across a reconnect would describe two different runs',
      );
    });
  });
}
