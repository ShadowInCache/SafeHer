import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/domain/models/motion_data.dart';

void main() {
  group('parseMotionPacket - all five classes', () {
    const cases = {
      'CLASS=NORMAL,CONFIDENCE=0.9726': ('NORMAL', 0.9726),
      'CLASS=SUDDEN_MOVEMENT,CONFIDENCE=0.8124': ('SUDDEN_MOVEMENT', 0.8124),
      'CLASS=SHAKING,CONFIDENCE=0.9000': ('SHAKING', 0.9000),
      'CLASS=TWISTING,CONFIDENCE=0.9400': ('TWISTING', 0.9400),
      'CLASS=FALL,CONFIDENCE=0.9613': ('FALL', 0.9613),
    };

    for (final MapEntry(key: packet, value: (expectedClass, expectedConfidence)) in cases.entries) {
      test('parses "$packet"', () {
        final result = parseMotionPacket(packet);
        expect(result, isNotNull);
        expect(result!.classification, expectedClass);
        expect(result.confidence, expectedConfidence);
      });
    }
  });

  group('parseMotionPacket - robustness against real notification framing', () {
    test('tolerates a trailing newline', () {
      expect(parseMotionPacket('CLASS=FALL,CONFIDENCE=0.9613\n'), const MotionData(classification: 'FALL', confidence: 0.9613));
    });

    test('tolerates a trailing \\r\\n', () {
      expect(parseMotionPacket('CLASS=FALL,CONFIDENCE=0.9613\r\n'), const MotionData(classification: 'FALL', confidence: 0.9613));
    });

    test('tolerates incidental surrounding whitespace', () {
      expect(parseMotionPacket('  CLASS=FALL,CONFIDENCE=0.9613  '), const MotionData(classification: 'FALL', confidence: 0.9613));
    });

    test('tolerates whitespace around the comma', () {
      expect(parseMotionPacket('CLASS=FALL, CONFIDENCE=0.9613'), const MotionData(classification: 'FALL', confidence: 0.9613));
    });

    test('repeated identical notifications each parse independently', () {
      const packet = 'CLASS=NORMAL,CONFIDENCE=0.9726';
      final first = parseMotionPacket(packet);
      final second = parseMotionPacket(packet);
      expect(first, second);
      expect(first, isNotNull);
    });
  });

  group('parseMotionPacket - the bare format SafeHer_Glove_V5_OnDevice sends', () {
    // Before this, only the keyed format parsed, so the Motion Risk card read
    // `--` against the firmware the glove actually runs.
    test('parses FALL,0.93', () {
      expect(parseMotionPacket('FALL,0.93'), const MotionData(classification: 'FALL', confidence: 0.93));
    });

    test('parses SUDDEN_MOVEMENT with a trailing \\r\\n', () {
      expect(
        parseMotionPacket('SUDDEN_MOVEMENT,0.81\r\n'),
        const MotionData(classification: 'SUDDEN_MOVEMENT', confidence: 0.81),
      );
    });

    test('bare and keyed payloads of the same reading are equal', () {
      expect(parseMotionPacket('FALL,0.9613'), parseMotionPacket('CLASS=FALL,CONFIDENCE=0.9613'));
    });

    test('a retired 7-class label is rejected in the bare format too', () {
      expect(parseMotionPacket('PUSH,0.90'), isNull);
    });

    test('a half-keyed packet is rejected, not guessed', () {
      expect(parseMotionPacket('FALL,CONFIDENCE=0.9'), isNull);
    });

    test('bare format with a bad confidence is rejected', () {
      expect(parseMotionPacket('FALL,abc'), isNull);
      expect(parseMotionPacket('FALL,1.5'), isNull);
    });
  });

  group('parseMotionPacket - malformed packets never throw, return null', () {
    test('missing confidence field entirely', () {
      expect(() => parseMotionPacket('CLASS=FALL'), returnsNormally);
      expect(parseMotionPacket('CLASS=FALL'), isNull);
    });

    test('unknown class name', () {
      expect(() => parseMotionPacket('CLASS=UNKNOWN,CONFIDENCE=0.8'), returnsNormally);
      expect(parseMotionPacket('CLASS=UNKNOWN,CONFIDENCE=0.8'), isNull);
    });

    test('non-numeric confidence', () {
      expect(() => parseMotionPacket('CLASS=FALL,CONFIDENCE=abc'), returnsNormally);
      expect(parseMotionPacket('CLASS=FALL,CONFIDENCE=abc'), isNull);
    });

    test('confidence above 1.0', () {
      expect(() => parseMotionPacket('CLASS=FALL,CONFIDENCE=1.5'), returnsNormally);
      expect(parseMotionPacket('CLASS=FALL,CONFIDENCE=1.5'), isNull);
    });

    test('confidence below 0.0', () {
      expect(parseMotionPacket('CLASS=FALL,CONFIDENCE=-0.1'), isNull);
    });

    test('empty string', () {
      expect(() => parseMotionPacket(''), returnsNormally);
      expect(parseMotionPacket(''), isNull);
    });

    test('only whitespace', () {
      expect(parseMotionPacket('   \r\n'), isNull);
    });

    test('completely unrelated garbage', () {
      expect(() => parseMotionPacket('not a packet at all'), returnsNormally);
      expect(parseMotionPacket('not a packet at all'), isNull);
    });

    test('extra unexpected fields', () {
      expect(parseMotionPacket('CLASS=FALL,CONFIDENCE=0.9613,EXTRA=1'), isNull);
    });

    test('empty class value', () {
      expect(parseMotionPacket('CLASS=,CONFIDENCE=0.9613'), isNull);
    });

    test('NaN confidence', () {
      expect(parseMotionPacket('CLASS=FALL,CONFIDENCE=NaN'), isNull);
    });
  });

  group('MotionData value semantics', () {
    test('equal classification+confidence compare equal', () {
      const a = MotionData(classification: 'FALL', confidence: 0.9613);
      const b = MotionData(classification: 'FALL', confidence: 0.9613);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('different confidence compares unequal', () {
      const a = MotionData(classification: 'FALL', confidence: 0.9613);
      const b = MotionData(classification: 'FALL', confidence: 0.5);
      expect(a, isNot(b));
    });
  });
}
