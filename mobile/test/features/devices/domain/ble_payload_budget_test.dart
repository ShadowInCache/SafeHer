import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/domain/ble_service.dart';
import 'package:safeher_app/features/devices/domain/glove_protocol.dart';

/// The glove's wire format has to fit the transport carrying it.
///
/// BLE's default ATT MTU is 23 bytes, of which 20 are payload. The longest
/// classification the firmware can send — `SUDDEN_MOVEMENT,0.93` — is
/// *exactly* 20. There is no headroom at all, and nothing anywhere said so:
/// neither end negotiated a larger MTU, and the limit is invisible in the
/// Dart and the C++ alike.
///
/// What that costs: one extra character — a longer class name from a retrained
/// model, a third decimal place, or the sequence number that would make a
/// dropped notification detectable — and notifications truncate. The app would
/// then drop them as unparsable, which it does silently and by design, because
/// a truncated packet is supposed to be a lost reading rather than a bad one.
/// A model change would quietly stop the glove raising alarms.
///
/// So the budget is asserted here. `kBleDesiredMtu` buys the headroom; these
/// tests make sure nobody spends it without noticing.
const _defaultAttPayload = 20; // 23-byte MTU minus the 3-byte ATT header

String _longestClassification() {
  final longest = GloveClassification.knownLabels.reduce(
    (a, b) => a.length >= b.length ? a : b,
  );
  // The firmware formats with `snprintf("%s,%.2f")`, so two decimals always.
  return '$longest,0.93';
}

void main() {
  group('the classification payload against the default MTU', () {
    test('today it fits, with nothing to spare', () {
      final payload = _longestClassification();

      expect(
        payload.length,
        lessThanOrEqualTo(_defaultAttPayload),
        reason: '"$payload" would be truncated on a 23-byte MTU, and the app '
            'drops truncated notifications silently',
      );
      expect(
        payload.length,
        _defaultAttPayload,
        reason: 'if this is no longer exactly at the limit the comment above '
            'is stale — check whether the headroom claim still holds',
      );
    });

    test('every known label fits', () {
      for (final label in GloveClassification.knownLabels) {
        expect(
          '$label,0.93'.length,
          lessThanOrEqualTo(_defaultAttPayload),
          reason: '$label does not fit the default ATT payload',
        );
      }
    });
  });

  group('the negotiated MTU', () {
    test('leaves real headroom over the default', () {
      expect(kBleDesiredMtu, greaterThan(23));
      expect(
        kBleDesiredMtu - 3,
        greaterThan(_defaultAttPayload),
        reason: 'negotiating an MTU that buys no payload is pointless',
      );
    });

    test('is big enough for a sequence number on the longest class', () {
      // The reason the headroom is wanted: GATT notifications are
      // unacknowledged, so without a sequence number a lost classification is
      // indistinguishable from a quiet second. `,4294967295` is the widest a
      // uint32 counter can render.
      final extended = '${_longestClassification()},4294967295';

      expect(
        extended.length,
        lessThanOrEqualTo(kBleDesiredMtu - 3),
        reason: 'the negotiated MTU must fit the payload it exists to allow',
      );
    });
  });
}
