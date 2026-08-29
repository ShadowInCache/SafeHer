import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/domain/glove_protocol.dart';
import 'package:safeher_app/features/devices/domain/glove_threat_detector.dart';

/// This class decides whether to summon people to someone's location. Both
/// directions of being wrong are expensive: a miss leaves someone hurt with
/// no alarm, and a false alarm is how people learn to switch the feature off,
/// after which it protects nobody at all.
GloveClassification _c(String label, double confidence) =>
    GloveClassification(label: label, confidence: confidence);

void main() {
  late GloveThreatDetector detector;
  final t0 = DateTime(2026, 8, 28, 12, 0, 0);

  setUp(() => detector = GloveThreatDetector());

  bool feed(GloveClassification c, {double threshold = 0.75, Duration at = Duration.zero}) =>
      detector.shouldTrigger(c, threshold: threshold, now: t0.add(at));

  group('a single reading is never enough', () {
    test('one FALL does not trigger', () {
      // A glove dropped on a table produces exactly this.
      expect(feed(_c('FALL', 0.99)), isFalse);
      expect(detector.pendingHits, 1);
    });
  });

  group('two readings inside the window do trigger', () {
    test('the second qualifying FALL fires', () {
      expect(feed(_c('FALL', 0.90)), isFalse);
      expect(
        feed(_c('FALL', 0.90), at: const Duration(seconds: 2)),
        isTrue,
        reason: 'a real fall produces more than one reading in a few seconds',
      );
    });

    test('an intervening NORMAL does not break the vote', () {
      // A real fall reports FALL, then NORMAL from the floor. Requiring an
      // unbroken run would miss exactly the event this exists to catch.
      expect(feed(_c('FALL', 0.90)), isFalse);
      expect(feed(_c('NORMAL', 0.99), at: const Duration(seconds: 1)), isFalse);
      expect(feed(_c('FALL', 0.90), at: const Duration(seconds: 2)), isTrue);
    });
  });

  group('readings outside the window do not accumulate', () {
    test('two FALLs a minute apart never trigger', () {
      expect(feed(_c('FALL', 0.95)), isFalse);
      expect(
        feed(_c('FALL', 0.95), at: const Duration(seconds: 60)),
        isFalse,
        reason: 'unrelated events on the same day must not add up to an alarm',
      );
    });

    test('an old hit is dropped, leaving only the new one pending', () {
      feed(_c('FALL', 0.95));
      feed(_c('FALL', 0.95), at: const Duration(seconds: 30));
      expect(detector.pendingHits, 1);
    });
  });

  group('the user threshold is respected', () {
    test('confidence below the threshold never counts', () {
      expect(feed(_c('FALL', 0.50), threshold: 0.75), isFalse);
      expect(feed(_c('FALL', 0.60), threshold: 0.75, at: const Duration(seconds: 1)), isFalse);
      expect(detector.pendingHits, 0, reason: 'a weak reading is not a hit at all');
    });

    test('a lower threshold makes it more sensitive', () {
      expect(feed(_c('FALL', 0.55), threshold: 0.50), isFalse);
      expect(feed(_c('FALL', 0.55), threshold: 0.50, at: const Duration(seconds: 1)), isTrue);
    });

    test('a threshold of 1.0 is effectively off for anything under certainty', () {
      for (var i = 0; i < 5; i++) {
        expect(
          feed(_c('FALL', 0.99), threshold: 1.0, at: Duration(seconds: i)),
          isFalse,
        );
      }
    });
  });

  group('only FALL auto-triggers', () {
    test('everyday motions never fire, however confident', () {
      // These are the classes most likely to come from ordinary handling.
      // Auto-dispatching them is a product decision to be made with data.
      for (final label in ['NORMAL', 'JERK', 'SHAKING', 'TWISTING']) {
        final d = GloveThreatDetector();
        for (var i = 0; i < 6; i++) {
          expect(
            d.shouldTrigger(_c(label, 0.99), threshold: 0.5, now: t0.add(Duration(seconds: i))),
            isFalse,
            reason: label,
          );
        }
      }
    });

    test('PUSH and PULL do not auto-trigger on their own', () {
      for (final label in ['PUSH', 'PULL']) {
        final d = GloveThreatDetector();
        for (var i = 0; i < 6; i++) {
          expect(
            d.shouldTrigger(_c(label, 0.99), threshold: 0.5, now: t0.add(Duration(seconds: i))),
            isFalse,
            reason: label,
          );
        }
      }
    });

    test('an unknown class from newer firmware does not fire', () {
      final d = GloveThreatDetector();
      for (var i = 0; i < 6; i++) {
        expect(
          d.shouldTrigger(_c('SPRINT', 0.99), threshold: 0.5, now: t0.add(Duration(seconds: i))),
          isFalse,
          reason: 'a class this build does not understand must not raise an alarm',
        );
      }
    });
  });

  group('cooldown', () {
    test('does not immediately re-fire after triggering', () {
      expect(feed(_c('FALL', 0.9)), isFalse);
      expect(feed(_c('FALL', 0.9), at: const Duration(seconds: 1)), isTrue);

      // Otherwise cancelling the alarm would start an argument with the phone.
      for (var i = 2; i < 10; i++) {
        expect(
          feed(_c('FALL', 0.9), at: Duration(seconds: i)),
          isFalse,
          reason: 'still inside the cooldown at ${i}s',
        );
      }
    });

    test('can fire again once the cooldown has passed', () {
      feed(_c('FALL', 0.9));
      expect(feed(_c('FALL', 0.9), at: const Duration(seconds: 1)), isTrue);

      expect(feed(_c('FALL', 0.9), at: const Duration(minutes: 3)), isFalse);
      expect(
        feed(_c('FALL', 0.9), at: const Duration(minutes: 3, seconds: 1)),
        isTrue,
        reason: 'a second genuine emergency later must still raise an alarm',
      );
    });
  });

  group('reset', () {
    test('clears pending hits so a dropout cannot span a window', () {
      feed(_c('FALL', 0.9));
      expect(detector.pendingHits, 1);

      detector.reset();

      expect(detector.pendingHits, 0);
      expect(
        feed(_c('FALL', 0.9), at: const Duration(seconds: 1)),
        isFalse,
        reason: 'readings from before a disconnect must not vote with ones after it',
      );
    });
  });
}
