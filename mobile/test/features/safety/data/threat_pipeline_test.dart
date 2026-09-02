import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/domain/glove_protocol.dart';
import 'package:safeher_app/features/safety/data/threat_pipeline.dart';

/// The glove reports a class and a confidence; the fusion engine consumes a
/// single number between 0 and 1. This is the translation, and it is where a
/// product decision about what counts as dangerous gets turned into arithmetic.
void main() {
  double score(String label, double confidence) => ThreatPipeline.gloveScore(
        GloveClassification(label: label, confidence: confidence),
      );

  group('glove class to threat score', () {
    test('a confident fall is the maximum', () {
      expect(score('FALL', 1.0), 1.0);
    });

    test('force applied by someone else outranks everyday movement', () {
      // PUSH and PULL describe another person acting on her. JERK, SHAKING and
      // TWISTING happen all day — a bag lifted, a hand dried, a jar opened.
      expect(score('PUSH', 1.0), greaterThan(score('SHAKING', 1.0)));
      expect(score('PULL', 1.0), greaterThan(score('TWISTING', 1.0)));
    });

    test('a fall outranks force, which outranks everyday movement', () {
      expect(score('FALL', 1.0), greaterThan(score('PUSH', 1.0)));
      expect(score('PUSH', 1.0), greaterThan(score('JERK', 1.0)));
    });

    test('normal movement contributes nothing', () {
      expect(score('NORMAL', 1.0), 0.0);
    });

    test('an unknown class from newer firmware scores zero, not a guess', () {
      // Firmware that adds an eighth class must not be silently mapped onto a
      // meaning it does not have. Zero is the safe reading: it contributes no
      // alarm, and the glove's own direct path is unaffected.
      expect(score('SOMETHING_NEW', 1.0), 0.0);
    });
  });

  group('confidence scales the result', () {
    test('an unsure fall is not the same claim as a certain one', () {
      expect(score('FALL', 0.5), lessThan(score('FALL', 1.0)));
      expect(score('FALL', 0.5), closeTo(0.5, 1e-9));
    });

    test('zero confidence contributes nothing whatever the class', () {
      for (final label in GloveClassification.knownLabels) {
        expect(score(label, 0.0), 0.0, reason: label);
      }
    });

    test('every class stays inside the fusion engine\'s range', () {
      for (final label in [...GloveClassification.knownLabels, 'UNKNOWN']) {
        for (final confidence in [0.0, 0.33, 0.75, 1.0]) {
          expect(score(label, confidence), inInclusiveRange(0.0, 1.0),
              reason: '$label at $confidence');
        }
      }
    });
  });

  group('pipeline status', () {
    test('nothing is running by default', () {
      const status = ThreatPipelineStatus();
      expect(status.armed, isFalse);
      expect(status.audioListening, isFalse);
      expect(status.weaponAvailable, isFalse);
      expect(status.glassesStreaming, isFalse);
    });

    test('yielding the microphone is not the same as being unavailable', () {
      // One is temporary and self-correcting; the other needs the user to do
      // something. The UI must not warn about the first.
      const yielded = ThreatPipelineStatus(
        armed: true,
        audioYieldedToEvidence: true,
      );

      expect(yielded.audioYieldedToEvidence, isTrue);
      expect(yielded.audioUnavailable, isFalse);
      expect(yielded.audioListening, isFalse);
    });

    test('copyWith leaves untouched fields alone', () {
      const before = ThreatPipelineStatus(
        armed: true,
        audioListening: true,
        weaponAvailable: true,
        weaponOnDevice: true,
      );

      final after = before.copyWith(audioListening: false);

      expect(after.audioListening, isFalse);
      expect(after.armed, isTrue);
      expect(after.weaponAvailable, isTrue);
      expect(after.weaponOnDevice, isTrue);
    });
  });
}
