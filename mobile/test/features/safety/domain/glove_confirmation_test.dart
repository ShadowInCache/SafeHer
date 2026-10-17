import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/safety/domain/glove_confirmation.dart';

/// Both of these are transcribed from real device logs of the same firmware.
/// The gate has to get both right: suppress the first, pass the second.
///
/// The first version of this class was tested only against the capture it had
/// to suppress. It passed, shipped, and on hardware blocked *everything* --
/// twenty-plus FALL readings, several at 0.99, none ever confirmed. A gate
/// tested only against the failure it was built for will happily block the
/// success nobody checked.
void main() {
  late DateTime t0;
  DateTime at(double seconds) => t0.add(Duration(milliseconds: (seconds * 1000).round()));

  setUp(() => t0 = DateTime(2026, 10, 17, 15, 0, 0));

  /// Feeds a capture. `hits` are seconds-offsets of threatening readings;
  /// `calm` are the NORMAL readings between them.
  int reportsFor(GloveConfirmation c, List<double> hits, {List<double> calm = const []}) {
    final events = <(double, bool)>[
      ...hits.map((s) => (s, true)),
      ...calm.map((s) => (s, false)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    var reported = 0;
    for (final (s, isHit) in events) {
      if (isHit) {
        if (c.confirm(at(s))) reported++;
      } else {
        c.observeCalm(at(s));
      }
    }
    return reported;
  }

  group('11 October capture — glove idle on a desk', () {
    // Three isolated spikes over eight seconds, then 30+ seconds of calm.
    // These drove fusion to `critical` six times with nobody touching it.
    const spikes = [1.0, 5.0, 9.0];
    const calm = [0.0, 2.0, 3.0, 6.0, 7.0, 10.0, 12.0, 20.0, 30.0];

    test('is suppressed entirely', () {
      expect(reportsFor(GloveConfirmation(), spikes, calm: calm), 0);
    });

    test('stays suppressed even though calm no longer resets the streak', () {
      // The fix removed reset-on-calm. This pins that the removal did not
      // quietly let the idle capture through.
      final c = GloveConfirmation();
      expect(reportsFor(c, spikes, calm: calm), 0);
      expect(c.hits, lessThan(c.requiredHits));
    });
  });

  group('17 October capture — glove deliberately moved', () {
    // Real timings from the device log, relative to 14:59:56.
    const readings = [0.0, 2.0, 3.5, 5.5, 7.0, 11.0, 14.0, 16.5, 18.0];
    // NORMAL readings interleave between every pair -- this is the alternation
    // that made the consecutive-run version unreachable.
    const calm = [1.0, 2.7, 4.5, 6.2, 9.0, 12.5, 15.2, 17.2];

    test('is reported, not blocked', () {
      expect(reportsFor(GloveConfirmation(), readings, calm: calm), greaterThan(0),
          reason: 'a real event must reach fusion despite interleaved NORMALs');
    });

    test('interleaved calm does not prevent confirmation', () {
      final c = GloveConfirmation();
      c.confirm(at(0.0));
      c.observeCalm(at(1.0));
      c.confirm(at(2.0));
      c.observeCalm(at(2.7));
      expect(c.confirm(at(3.5)), isTrue,
          reason: 'three hits inside the window, calm between them');
    });
  });

  group('the density rule', () {
    test('two hits in the window are not enough', () {
      final c = GloveConfirmation();
      expect(c.confirm(at(0)), isFalse);
      expect(c.confirm(at(1)), isFalse);
    });

    test('three hits inside the window confirm', () {
      final c = GloveConfirmation();
      c.confirm(at(0));
      c.confirm(at(1));
      expect(c.confirm(at(2)), isTrue);
    });

    test('three hits spread beyond the window do not', () {
      final c = GloveConfirmation();
      expect(c.confirm(at(0)), isFalse);
      expect(c.confirm(at(4)), isFalse);
      expect(c.confirm(at(9)), isFalse, reason: 'the first has aged out');
    });

    test('hits age out of the window', () {
      final c = GloveConfirmation();
      c.confirm(at(0));
      c.confirm(at(1));
      c.observeCalm(at(10));
      expect(c.hits, 0);
    });

    test('a sustained event keeps reporting once confirmed', () {
      final c = GloveConfirmation();
      c.confirm(at(0));
      c.confirm(at(1));
      expect(c.confirm(at(2)), isTrue);
      expect(c.confirm(at(3)), isTrue);
    });
  });

  group('lifecycle', () {
    test('reset clears everything for the next journey', () {
      final c = GloveConfirmation();
      c.confirm(at(0));
      c.confirm(at(1));
      c.reset();
      expect(c.hits, 0);
      expect(c.confirm(at(2)), isFalse, reason: 'streak must not survive a reset');
    });

    test('requiredHits of 1 reports immediately', () {
      expect(GloveConfirmation(requiredHits: 1).confirm(at(0)), isTrue);
    });
  });
}
