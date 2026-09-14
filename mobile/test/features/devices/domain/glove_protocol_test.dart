import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/domain/glove_protocol.dart';
import 'package:safeher_app/shared/models/threat_level.dart';

/// Pins the wire contract with `glove/firmware/SafeHer_Glove_V5_OnDevice.ino`.
///
/// The firmware and the app are separate codebases that have to agree
/// exactly. When they did not, the failure was silent: the glove paired,
/// notified into nothing, and the app showed hardcoded zeros. These tests are
/// the thing that turns a future disagreement into a red build.
void main() {
  group('GloveClassification.tryParse', () {
    test('parses what the firmware sends', () {
      final result = GloveClassification.tryParse('FALL,0.93')!;

      expect(result.label, 'FALL');
      expect(result.confidence, closeTo(0.93, 1e-9));
      expect(result.isKnown, isTrue);
    });

    test('accepts the firmware boot value', () {
      // setValue("NORMAL,0.00") runs before the first inference.
      final result = GloveClassification.tryParse('NORMAL,0.00')!;
      expect(result.label, 'NORMAL');
      expect(result.confidence, 0);
    });

    test('every trained class round-trips', () {
      for (final label in GloveClassification.knownLabels) {
        final parsed = GloveClassification.tryParse('$label,0.5');
        expect(parsed, isNotNull, reason: label);
        expect(parsed!.label, label);
        expect(parsed.isKnown, isTrue);
      }
    });

    test('tolerates whitespace and lower case', () {
      final result = GloveClassification.tryParse('  fall , 0.80 ')!;
      expect(result.label, 'FALL');
      expect(result.confidence, closeTo(0.80, 1e-9));
    });

    test('an unknown label parses but is flagged, not dropped', () {
      // Firmware that adds an eighth class should surface as unknown rather
      // than crash the parser or be mapped to something wrong.
      final result = GloveClassification.tryParse('SPRINT,0.7')!;
      expect(result.label, 'SPRINT');
      expect(result.isKnown, isFalse);
      expect(result.threatLevel, ThreatLevel.safe);
    });

    test('confidence is clamped to a probability', () {
      expect(GloveClassification.tryParse('FALL,1.4')!.confidence, 1.0);
      expect(GloveClassification.tryParse('FALL,-0.2')!.confidence, 0.0);
    });

    test('malformed payloads are dropped, never thrown', () {
      // BLE notifications arrive truncated often enough that a throwing
      // parser would take the app down in the field.
      for (final bad in ['', 'FALL', 'FALL,', ',0.9', 'FALL,abc', ',', '   ']) {
        expect(GloveClassification.tryParse(bad), isNull, reason: 'input: "$bad"');
      }
    });
  });

  group('threat mapping', () {
    test('only FALL is danger', () {
      expect(GloveClassification.tryParse('FALL,0.9')!.threatLevel, ThreatLevel.danger);
    });

    test('SUDDEN_MOVEMENT is elevated: force applied by someone else', () {
      expect(GloveClassification.tryParse('SUDDEN_MOVEMENT,0.9')!.threatLevel, ThreatLevel.elevated);
    });

    test('everyday motions stay at caution', () {
      // A bag lifted, a hand dried, a jar opened. Escalating these is how
      // people learn to switch the feature off, and a disabled feature
      // protects nobody.
      for (final label in ['SHAKING', 'TWISTING']) {
        expect(
          GloveClassification.tryParse('$label,0.95')!.threatLevel,
          ThreatLevel.caution,
          reason: label,
        );
      }
    });

    test('NORMAL is safe even at high confidence', () {
      expect(GloveClassification.tryParse('NORMAL,0.99')!.threatLevel, ThreatLevel.safe);
    });

    test('confidence does not change the level', () {
      // The level describes what the movement looked like. Whether it is
      // acted on is the threshold's decision, not this mapping's.
      expect(GloveClassification.tryParse('FALL,0.05')!.threatLevel, ThreatLevel.danger);
    });
  });

  group('display', () {
    test('shouty firmware labels become sentence case', () {
      expect(GloveClassification.tryParse('FALL,0.9')!.displayLabel, 'Fall');
      expect(GloveClassification.tryParse('TWISTING,0.9')!.displayLabel, 'Twisting');
    });
  });

  group('GloveTelemetry.tryParse', () {
    test('parses a full tick', () {
      final t = GloveTelemetry.tryParse('1.02,4.3,78,86')!;

      expect(t.accelG, closeTo(1.02, 1e-9));
      expect(t.gyroDps, closeTo(4.3, 1e-9));
      expect(t.heartRateBpm, closeTo(78, 1e-9));
      expect(t.batteryPercent, closeTo(86, 1e-9));
    });

    test('a short payload leaves later fields unknown, not zero', () {
      // Firmware that has not implemented the pulse sensor yet should not
      // make the app claim a heart rate of zero.
      final t = GloveTelemetry.tryParse('1.02,4.3')!;

      expect(t.accelG, isNotNull);
      expect(t.gyroDps, isNotNull);
      expect(t.heartRateBpm, isNull);
      expect(t.batteryPercent, isNull);
    });

    test('a single unparsable field does not discard the rest', () {
      final t = GloveTelemetry.tryParse('1.02,nan,78,86')!;

      expect(t.accelG, isNotNull);
      expect(t.gyroDps, isNull);
      expect(t.heartRateBpm, closeTo(78, 1e-9));
    });

    test('battery is clamped to a percentage', () {
      expect(GloveTelemetry.tryParse('0,0,0,140')!.batteryPercent, 100);
    });

    test('a battery reading of zero is no sensor, not a flat battery', () {
      // The glove is transmitting, so it plainly has power. Zero here only
      // ever means the firmware does not measure it -- and a negative reading
      // is a broken ADC, which clamps to zero and means the same thing.
      expect(GloveTelemetry.tryParse('1.02,4.3,78,0')!.batteryPercent, isNull);
      expect(GloveTelemetry.tryParse('0,0,0,-5')!.batteryPercent, isNull);
    });

    test('a heart rate of zero is no sensor, not a stopped heart', () {
      // The firmware sends 0 for bpm precisely to avoid fabricating data.
      // Reading it as a measurement would put "0 bpm" on the device card,
      // which is the claim it was trying not to make.
      expect(GloveTelemetry.tryParse('1.02,4.3,0,86')!.heartRateBpm, isNull);
    });

    test('a payload with nothing usable is dropped', () {
      for (final bad in ['', '   ', 'abc', 'abc,def']) {
        expect(GloveTelemetry.tryParse(bad), isNull, reason: 'input: "$bad"');
      }
    });

    test('zero motion is a real reading, not an absence', () {
      // A glove lying still genuinely reports 0.00g and 0.0 dps, and those
      // must survive as values rather than being mistaken for "no data".
      // Only bpm and battery get the implausible-zero rule.
      final t = GloveTelemetry.tryParse('0,0,0,0')!;
      expect(t.hasAny, isTrue);
      expect(t.accelG, 0);
      expect(t.gyroDps, 0);
      expect(t.heartRateBpm, isNull);
      expect(t.batteryPercent, isNull);
    });

    test('the exact payloads the current firmware emits', () {
      // Copied from SafeHer_Glove_V5_OnDevice.ino: the initial characteristic
      // value set in initializeBLE, and a live tick from sendTelemetry, which
      // formats "%.2f,%.1f,%.0f,%.0f" with bpm and battery hardcoded to zero.
      // If the firmware's wire format drifts, this is the test that says so.
      final initial = GloveTelemetry.tryParse('0.00,0.0,0,0')!;
      expect(initial.accelG, 0);
      expect(initial.heartRateBpm, isNull);

      final live = GloveTelemetry.tryParse('1.02,4.3,0,0')!;
      expect(live.accelG, closeTo(1.02, 1e-9));
      expect(live.gyroDps, closeTo(4.3, 1e-9));
      expect(live.heartRateBpm, isNull, reason: 'never "0 bpm" on the card');
      expect(live.batteryPercent, isNull);
    });

    test('a two-field payload is what the firmware should send instead', () {
      // The recommended firmware fix: send only the fields it measures. The
      // app already reads that correctly, which is why no app change is
      // needed when the firmware is corrected.
      final t = GloveTelemetry.tryParse('1.02,4.3')!;
      expect(t.accelG, closeTo(1.02, 1e-9));
      expect(t.heartRateBpm, isNull);
      expect(t.batteryPercent, isNull);
    });
  });

  group('BLE identifiers match the firmware', () {
    test('service and characteristic UUIDs are the ones flashed', () {
      // Hardcoded on both sides; if the firmware changes these, this test is
      // the reminder that the app has to change with it.
      expect(GloveBle.deviceName, 'SafeHer-Glove');
      expect(GloveBle.serviceUuid, '4fafc201-1fb5-459e-8fcc-c5c9c331914b');
      expect(
        GloveBle.classificationCharacteristicUuid,
        'beb5483e-36e1-4688-b7f5-ea07361b26a8',
      );
      expect(
        GloveBle.telemetryCharacteristicUuid,
        '33b4fb00-9c17-4ad2-8fc9-89ad6dbc76bd',
      );
    });

    test('the class list matches CLASS_NAMES, in the firmware order', () {
      // The firmware notifies a label by indexing CLASS_NAMES with the model's
      // predicted class. Order is therefore part of the wire contract, not a
      // presentation detail: a list that drifts here would map a fall onto
      // some other word without anything failing.
      expect(GloveClassification.knownLabels, [
        'NORMAL',
        'SUDDEN_MOVEMENT',
        'SHAKING',
        'TWISTING',
        'FALL',
      ]);
    });

    test("the firmware's initial classification value is safe and parseable", () {
      // initializeBLE seeds the characteristic with "NORMAL,0.00". Some stacks
      // deliver that as the first read on subscribe, so it must parse, and it
      // must not look like a threat.
      final initial = GloveClassification.tryParse('NORMAL,0.00')!;
      expect(initial.label, 'NORMAL');
      expect(initial.threatLevel, ThreatLevel.safe);
    });
  });
}
