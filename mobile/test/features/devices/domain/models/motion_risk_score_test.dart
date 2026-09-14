import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/domain/models/motion_data.dart';
import 'package:safeher_app/features/devices/domain/models/motion_risk_score.dart';

void main() {
  double score(String classification, double confidence) =>
      computeMotionRiskScore(MotionData(classification: classification, confidence: confidence));

  group('computeMotionRiskScore', () {
    test('NORMAL is always 0 regardless of confidence', () {
      expect(score('NORMAL', 0.9990), 0.0);
      expect(score('NORMAL', 0.50), 0.0);
      expect(score('NORMAL', 0.99), 0.0);
      expect(score('NORMAL', 1.00), 0.0);
    });

    test('SUDDEN_MOVEMENT + 0.8124 -> 40.62', () {
      expect(score('SUDDEN_MOVEMENT', 0.8124), closeTo(40.62, 0.01));
    });

    test('SHAKING + 0.9000 -> 45.00', () {
      expect(score('SHAKING', 0.9000), closeTo(45.00, 0.01));
    });

    test('TWISTING + 0.9400 -> 47.00', () {
      expect(score('TWISTING', 0.9400), closeTo(47.00, 0.01));
    });

    test('FALL + 0.9613 -> 96.13', () {
      expect(score('FALL', 0.9613), closeTo(96.13, 0.01));
    });

    test('score is always within [0, 100]', () {
      for (final classification in kKnownMotionClasses) {
        for (final confidence in [0.0, 0.25, 0.5, 0.75, 1.0]) {
          final result = score(classification, confidence);
          expect(result, inInclusiveRange(0.0, 100.0));
        }
      }
    });
  });
}
