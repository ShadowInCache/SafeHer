/// The glove's raw motion classification result for one inference window,
/// exactly as sent over BLE by
/// `glove/firmware/SafeHer_Glove_Final/SafeHer_Glove_Final.ino`.
///
/// "Raw" is deliberate: neither this type nor [parseMotionPacket] judge how
/// dangerous a class is, or turn `FALL` + high confidence into anything
/// resembling a threat level. That judgement belongs entirely to the
/// team's Threat Score, which lives elsewhere in this app and is not
/// referenced, imported, or modified by this file.
class MotionData {
  const MotionData({required this.classification, required this.confidence});

  /// One of [kKnownMotionClasses]: NORMAL, SUDDEN_MOVEMENT, SHAKING,
  /// TWISTING, or FALL. [parseMotionPacket] already rejects anything else,
  /// so a valid [MotionData] instance is guaranteed to carry a known class.
  final String classification;

  /// The on-device model's confidence in [classification], 0.0-1.0
  /// inclusive. This is model confidence, not a danger score — a low
  /// number means "the model is unsure which class this is", not "this
  /// activity is safe".
  final double confidence;

  @override
  String toString() => 'MotionData(classification: $classification, confidence: $confidence)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MotionData && other.classification == classification && other.confidence == confidence;

  @override
  int get hashCode => Object.hash(classification, confidence);
}

/// The exact classes the glove's on-device V7 model can predict. Mirrors
/// `CLASS_NAMES[]` in `SafeHer_Glove_V5_OnDevice.ino` and nothing else —
/// this is a validity check for incoming packets, not a scoring policy.
/// Order does not matter here (unlike the firmware's array, which is
/// index-mapped to the model's class IDs); this is only ever used for
/// membership tests. `PUSH`/`PULL`/`JERK` were merged into `SUDDEN_MOVEMENT`.
const kKnownMotionClasses = {'NORMAL', 'SUDDEN_MOVEMENT', 'SHAKING', 'TWISTING', 'FALL'};

/// Parses one notification payload from the glove's BLE result characteristic
/// (see [MotionData]). Both firmware formats are accepted:
/// `FALL,0.93` from `SafeHer_Glove_V5_OnDevice` (the sketch to flash) and
/// `CLASS=FALL,CONFIDENCE=0.9300` from `SafeHer_Glove_Final`. Accepting only
/// the second left this card reading `--` against the current firmware while
/// the alarm path, which reads the first, worked.
///
/// Returns `null` — never throws — for anything that does not cleanly
/// match: a missing field, a class outside [kKnownMotionClasses], or a
/// confidence that is not a finite number in `[0.0, 1.0]`. Trailing
/// `\r`/`\n` and incidental whitespace around either field are tolerated.
/// Repeated identical notifications are not treated as an error — each is
/// parsed independently, exactly as received.
MotionData? parseMotionPacket(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final parts = trimmed.split(',');
  if (parts.length != 2) return null;

  String? classification;
  double? confidence;

  for (final part in parts) {
    final piece = part.trim();
    if (piece.startsWith('CLASS=')) {
      classification = piece.substring('CLASS='.length).trim();
    } else if (piece.startsWith('CONFIDENCE=')) {
      confidence = double.tryParse(piece.substring('CONFIDENCE='.length).trim());
    }
  }

  // Bare `FALL,0.93`. Only when no field is keyed at all, so a half-keyed
  // packet like `CLASS=,CONFIDENCE=0.9` is still rejected rather than guessed.
  if (classification == null && confidence == null && !trimmed.contains('=')) {
    classification = parts[0].trim();
    confidence = double.tryParse(parts[1].trim());
  }

  if (classification == null || !kKnownMotionClasses.contains(classification)) return null;
  if (confidence == null || !confidence.isFinite || confidence < 0.0 || confidence > 1.0) return null;

  return MotionData(classification: classification, confidence: confidence);
}
