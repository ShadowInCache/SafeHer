import 'dart:math';

/// A random UUID v4, without taking a dependency for it.
///
/// Exists because the emergency incident id has to be chosen *on the device*,
/// before the alert is sent. That is what makes a retry safe: a phone that
/// never heard back cannot know whether its request arrived, and without a
/// stable id every retry filed a second emergency and messaged every contact
/// again.
///
/// [Random.secure] rather than the default generator. Not because the id is a
/// secret — it is not, and every route that accepts one still checks
/// ownership — but because the default `Random` is seeded from the clock, and
/// two phones triggering an SOS in the same millisecond is exactly the
/// correlated event this id has to stay unique across.
String newUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));

  // Version 4 and the RFC 4122 variant, per §4.4. Set explicitly so the value
  // is a well-formed UUID rather than 32 random hex digits that merely look
  // like one — anything parsing it as a UUID would otherwise reject it.
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
