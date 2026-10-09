import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/network/api_time.dart';

/// Regression tests for the bug that made a 15-minute journey render as
/// "5h 18m overdue" on an IST phone: the backend sent `2026-10-09T08:44:00`
/// with no offset and `DateTime.parse` read it as local time.
void main() {
  group('tryParseApiTime', () {
    test('reads an offset-less timestamp as UTC, not local', () {
      final parsed = tryParseApiTime('2026-10-09T08:44:00')!;
      expect(parsed.isUtc, isTrue);
      expect(
        parsed.millisecondsSinceEpoch,
        DateTime.utc(2026, 10, 9, 8, 44).millisecondsSinceEpoch,
      );
    });

    test('honours an explicit Z', () {
      final parsed = tryParseApiTime('2026-10-09T08:44:00Z')!;
      expect(
        parsed.millisecondsSinceEpoch,
        DateTime.utc(2026, 10, 9, 8, 44).millisecondsSinceEpoch,
      );
    });

    test('honours an explicit +00:00, which is what the backend now sends', () {
      final parsed = tryParseApiTime('2026-10-09T08:44:00+00:00')!;
      expect(
        parsed.millisecondsSinceEpoch,
        DateTime.utc(2026, 10, 9, 8, 44).millisecondsSinceEpoch,
      );
    });

    test('converts a non-UTC offset rather than relabelling it', () {
      // 14:14+05:30 is 08:44 UTC — the same instant as the cases above.
      final parsed = tryParseApiTime('2026-10-09T14:14:00+05:30')!;
      expect(
        parsed.millisecondsSinceEpoch,
        DateTime.utc(2026, 10, 9, 8, 44).millisecondsSinceEpoch,
      );
    });

    test('the date separators are not mistaken for a negative offset', () {
      // Naive. If `-` in `2026-10-09` were read as an offset this would be
      // treated as already-zoned and left as local time.
      final parsed = tryParseApiTime('2026-10-09T08:44:00')!;
      expect(parsed.isUtc, isTrue);
    });

    test('handles a negative offset', () {
      final parsed = tryParseApiTime('2026-10-09T03:44:00-05:00')!;
      expect(
        parsed.millisecondsSinceEpoch,
        DateTime.utc(2026, 10, 9, 8, 44).millisecondsSinceEpoch,
      );
    });

    test('keeps sub-second precision', () {
      final parsed = tryParseApiTime('2026-10-09T08:44:00.250')!;
      expect(parsed.millisecond, 250);
      expect(parsed.isUtc, isTrue);
    });

    test('returns null for null, empty and malformed input', () {
      expect(tryParseApiTime(null), isNull);
      expect(tryParseApiTime(''), isNull);
      expect(tryParseApiTime('not a date'), isNull);
      expect(tryParseApiTime(42), isNull);
    });
  });

  group('parseApiTime', () {
    test('parses like tryParseApiTime', () {
      expect(parseApiTime('2026-10-09T08:44:00').isUtc, isTrue);
    });

    test('throws on malformed input', () {
      expect(() => parseApiTime('nonsense'), throwsFormatException);
    });
  });

  group('the original failure', () {
    test('a fresh 15-minute journey is not born overdue in IST', () {
      // The exact payload from the bug report: started 08:44 UTC, due 08:59
      // UTC. The phone's clock read 14:17 IST, which is 08:47 UTC — three
      // minutes in, twelve minutes left.
      final expectedArrival = parseApiTime('2026-10-09T08:59:00+00:00');
      final nowOnThePhone = DateTime.utc(2026, 10, 9, 8, 47);

      final remaining = expectedArrival.difference(nowOnThePhone);

      expect(remaining.isNegative, isFalse, reason: 'journey must not be overdue');
      expect(remaining.inMinutes, 12);
    });

    test('the offset-less form that caused it now yields the same instant', () {
      expect(
        parseApiTime('2026-10-09T08:59:00').millisecondsSinceEpoch,
        parseApiTime('2026-10-09T08:59:00+00:00').millisecondsSinceEpoch,
      );
    });
  });
}
