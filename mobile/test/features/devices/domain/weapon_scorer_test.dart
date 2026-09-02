import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/domain/weapon_scorer.dart';

/// `weapon` carries the largest weight in the fusion engine, because a knife
/// is the least ambiguous thing the system can see. That weight is only
/// deserved if the score behind it means something — so these tests are mostly
/// about refusing to be impressed by one frame.
///
/// The detector's own numbers set the shape of the problem. Recall 0.827 means
/// a genuine weapon is missed in roughly one frame in six, so a real weapon
/// produces an *intermittent* signal. A rule demanding an unbroken run would
/// miss real weapons; a rule accepting a single frame would fire on a poster.
void main() {
  final t0 = DateTime(2026, 9, 1, 12, 0, 0);

  // Frames arrive at ~2 fps -- the rate the phone samples the glasses stream
  // for inference. Five frames therefore span 2 seconds, comfortably inside
  // the scorer's 3-second staleness timeout. Spacing them a second apart, as
  // an earlier version of this file did, expires the oldest frame mid-window
  // and quietly tests something else.
  DateTime at(int frame) => t0.add(Duration(milliseconds: frame * 500));

  WeaponDetection knife(double confidence, DateTime when) =>
      WeaponDetection(label: 'knife', confidence: confidence, at: when);

  group('one frame is not evidence', () {
    test('a single confident detection scores low', () {
      final scorer = WeaponScorer();
      final score = scorer.observe([knife(0.95, at(0))], now: at(0));

      expect(score.qualifyingFrames, 1);
      expect(
        score.value,
        lessThan(0.30),
        reason: 'a reflection or a poster must not reach the alarm on its own',
      );
      expect(score.isPersistent, isFalse);
    });

    test('the flickering sequence from the design note stays low', () {
      // 0.42, 0.08, 0.03 -- exactly the pattern that should not count.
      final scorer = WeaponScorer();
      scorer.observe([knife(0.42, at(0))], now: at(0));
      scorer.observe([knife(0.08, at(1))], now: at(1));
      final score = scorer.observe([knife(0.03, at(2))], now: at(2));

      expect(score.qualifyingFrames, 0, reason: 'none of these clears the floor');
      expect(score.value, 0);
    });

    test('the persistent sequence from the design note scores strongly', () {
      // 0.84, 0.88, 0.86 -- a weapon that is actually there.
      final scorer = WeaponScorer();
      for (var i = 0; i < 5; i++) {
        scorer.observe([knife(0.84 + (i % 3) * 0.02, at(i))], now: at(i));
      }
      final score = scorer.current(now: at(4));

      expect(score.qualifyingFrames, 5);
      expect(score.value, greaterThan(0.80));
      expect(score.isPersistent, isTrue);
      expect(score.strongestLabel, 'knife');
    });
  });

  group('an intermittent real weapon still registers', () {
    test('missing one frame in six does not collapse the score', () {
      // What recall 0.827 actually looks like frame to frame.
      final scorer = WeaponScorer();
      final pattern = [0.88, 0.0, 0.85, 0.90, 0.86];
      for (var i = 0; i < pattern.length; i++) {
        scorer.observe(
          pattern[i] == 0 ? const [] : [knife(pattern[i], at(i))],
          now: at(i),
        );
      }
      final score = scorer.current(now: at(4));

      expect(score.qualifyingFrames, 4);
      expect(
        score.value,
        greaterThan(0.60),
        reason: 'a real weapon the model blinks on must still score highly',
      );
    });
  });

  group('an empty frame is an observation, not silence', () {
    test('empty frames stop the score rising, then age the hit out', () {
      // Persistence is measured against the window, not against however many
      // frames arrived, so looking and seeing nothing does not itself subtract.
      // What it does is occupy slots -- which is how a lone detection decays.
      final scorer = WeaponScorer();
      scorer.observe([knife(0.90, at(0))], now: at(0));
      final lone = scorer.current(now: at(0)).value;

      for (var i = 1; i < 5; i++) {
        scorer.observe(const [], now: at(i));
      }
      final stillOneHit = scorer.current(now: at(4)).value;

      expect(stillOneHit, closeTo(lone, 1e-9),
          reason: 'one hit in a five-frame window, however many blanks follow');
      expect(lone, lessThan(0.30), reason: 'and it was never a strong signal');

      // Six more blank frames push the hit out entirely.
      for (var i = 5; i < 11; i++) {
        scorer.observe(const [], now: at(i));
      }
      expect(scorer.current(now: at(10)).value, 0);
    });

    test('a full window of nothing scores zero', () {
      final scorer = WeaponScorer();
      for (var i = 0; i < 6; i++) {
        scorer.observe(const [], now: at(i));
      }

      expect(scorer.current(now: at(5)).value, 0);
    });
  });

  group('a gap in the stream cannot be voted across', () {
    test('stale frames expire', () {
      // The same failure the glove's detector guards against: readings from
      // before a dropout combining with readings after it into a run that
      // never happened inside one window.
      final scorer = WeaponScorer(frameTimeout: const Duration(seconds: 3));
      scorer.observe([knife(0.90, at(0))], now: at(0));
      scorer.observe([knife(0.92, at(1))], now: at(1));

      final afterGap = scorer.observe([knife(0.91, at(30))], now: at(30));

      expect(
        afterGap.qualifyingFrames,
        1,
        reason: 'the two frames from before the gap must not still be voting',
      );
      expect(afterGap.value, lessThan(0.30));
    });

    test('reset clears the window', () {
      final scorer = WeaponScorer();
      for (var i = 0; i < 5; i++) {
        scorer.observe([knife(0.90, at(i))], now: at(i));
      }
      expect(scorer.current(now: at(4)).value, greaterThan(0.8));

      scorer.reset();
      expect(scorer.current(now: at(4)).value, 0);
    });
  });

  group('the score is in the range the fusion engine expects', () {
    test('never leaves 0..1', () {
      final scorer = WeaponScorer();
      for (var i = 0; i < 10; i++) {
        final score = scorer.observe([knife(1.0, at(i))], now: at(i));
        expect(score.value, inInclusiveRange(0.0, 1.0));
      }
    });

    test('a maximal persistent weapon reaches the top of the scale', () {
      final scorer = WeaponScorer();
      for (var i = 0; i < 5; i++) {
        scorer.observe([knife(1.0, at(i))], now: at(i));
      }

      expect(scorer.current(now: at(4)).value, closeTo(1.0, 1e-9));
    });

    test('the strongest detection is carried for the incident record', () {
      final scorer = WeaponScorer();
      scorer.observe([knife(0.70, at(0))], now: at(0));
      scorer.observe(
        [WeaponDetection(label: 'pistol', confidence: 0.93, at: at(1))],
        now: at(1),
      );

      final score = scorer.current(now: at(1));
      expect(score.strongestLabel, 'pistol');
      expect(score.strongestConfidence, closeTo(0.93, 1e-9));
    });
  });
}
