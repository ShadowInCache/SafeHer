import 'motion_data.dart';

/// Per-class severity used only to derive [motionRiskScore] — a distinct,
/// glove-local signal separate from the app's overall Threat Score (owned
/// elsewhere and not read, referenced, or modified here). `NORMAL` is 0.0
/// so no confidence in "nothing is happening" can ever raise the score;
/// `FALL` is the only class scored at full severity.
const Map<String, double> kMotionSeverity = {
  'NORMAL': 0.0,
  'JERK': 0.50,
  'PUSH': 0.50,
  'PULL': 0.50,
  'SHAKING': 0.50,
  'TWISTING': 0.50,
  'FALL': 1.00,
};

/// `severity(classification) * confidence * 100`, in `[0.0, 100.0]`.
///
/// [MotionData.confidence] is the model's confidence in *which class* this
/// is, not a danger level — multiplying it by `NORMAL`'s zero severity is
/// what keeps a confident NORMAL reading at 0 rather than near 100.
double computeMotionRiskScore(MotionData data) {
  final severity = kMotionSeverity[data.classification] ?? 0.0;
  return severity * data.confidence * 100;
}
