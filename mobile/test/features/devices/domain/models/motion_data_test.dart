import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/domain/models/motion_data.dart';

void main() {
  group('parseMotionPacket - all seven classes', () {
    const cases = {
      'CLASS=NORMAL,CONFIDENCE=0.9726': ('NORMAL', 0.9726),
      'CLASS=PUSH,CONFIDENCE=0.8124': ('PUSH', 0.8124),
      'CLASS=PULL,CONFIDENCE=0.7341': ('PULL', 0.7341),
      'CLASS=JERK,CONFIDENCE=0.6500': ('JERK', 0.6500),
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
