/// Parsing for timestamps that arrive from the backend.
///
/// **Why this exists.** `DateTime.parse` treats an ISO string with no timezone
/// designator as *local* time. The backend stores every timestamp naive but
/// meaning UTC, and for a long time it serialised them that way too — so a
/// phone in IST read `2026-10-09T08:44:00` as 08:44 local, placing a journey
/// that had just started five and a half hours in the past and rendering it
/// as badly overdue.
///
/// The server now sends an explicit `+00:00` offset, which fixes this at the
/// source. These helpers are the second line of defence: a timestamp that
/// still arrives without an offset is read as UTC rather than silently
/// adopting whatever timezone the phone happens to be in. Being wrong by the
/// user's UTC offset is not acceptable in an app where a deadline decides
/// whether her contacts get called.
///
/// Date-only values (`2026-10-09`, used for dashboard day buckets) are *not*
/// timestamps and must not go through here — tagging them UTC shifts the day
/// for anyone east or west of Greenwich.
library;

/// True when an ISO-8601 string carries a `Z` or a `±HH:MM` offset.
bool _hasTimezone(String value) {
  if (value.endsWith('Z') || value.endsWith('z')) return true;
  // Only look past the date, so the '-' separators in `2026-10-09` are not
  // mistaken for a negative offset.
  final timeStart = value.indexOf('T');
  if (timeStart < 0) return false;
  final time = value.substring(timeStart);
  return time.contains('+') || time.contains('-');
}

/// Parses a backend timestamp, assuming UTC when no offset is given.
///
/// Throws [FormatException] on an unparseable value, like `DateTime.parse`.
DateTime parseApiTime(String value) {
  final parsed = tryParseApiTime(value);
  if (parsed == null) throw FormatException('Not an ISO-8601 timestamp', value);
  return parsed;
}

/// Parses a backend timestamp, or returns null. Assumes UTC when no offset is
/// given. Returns null for null, empty or malformed input.
DateTime? tryParseApiTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  // `DateTime.parse` already flags the offset-bearing case as UTC for `Z`;
  // for `+05:30` it converts and reports local. Either is correct. Only the
  // bare form needs reinterpreting.
  if (_hasTimezone(value)) return parsed;
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  );
}
