import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/safety/domain/glove_confirmation.dart';

/// The measurement behind this class: with the glove sitting on a desk and
/// nobody touching it, isolated `FALL` windows drove fusion to `critical` six
/// times in four minutes. Because the glove was the only reporting modality,
/// its score became the fused score outright.
void main() {
  late DateTime now;
  DateTime tick([int seconds = 1]) => now = now.add(Duration(seconds: seconds));

  setUp(() => now = DateTime(2026, 10, 11, 23, 47, 30));

  group('a single spike', () {
    test('is not reported on its own', () {
      final c = GloveConfirmation();
      expect(c.confirm(now), isFalse, reason: 'one window is not a fall');
    });

    test('is forgotten once the glove reports calm', () {
      final c = GloveConfirmation();
      expect(c.confirm(now), isFalse);
      c.reset(); // NORMAL
      expect(c.confirm(tick()), isFalse,
          reason: 'calm between two spikes separates them');
    });
  });

  group('a sustained event', () {
    test('is reported on the second consecutive reading', () {
      final c = GloveConfirmation();
      expect(c.confirm(now), isFalse);
      expect(c.confirm(tick()), isTrue);
    });

    test('keeps reporting while it continues', () {
      final c = GloveConfirmation();
      c.confirm(now);
      expect(c.confirm(tick()), isTrue);
      expect(c.confirm(tick()), isTrue, reason: 'a fall stays fallen');
    });
  });

  group('the streak window', () {
    test('two spikes far apart do not combine', () {
      final c = GloveConfirmation(window: Duration(seconds: 5));
      expect(c.confirm(now), isFalse);
      expect(c.confirm(tick(30)), isFalse,
          reason: 'a stale partial streak restarts rather than completing');
    });

    test('two spikes inside the window do combine', () {
      final c = GloveConfirmation(window: Duration(seconds: 5));
      expect(c.confirm(now), isFalse);
      expect(c.confirm(tick(3)), isTrue);
    });
  });

  group('configuration', () {
    test('requiredHits of 1 reports immediately', () {
      expect(GloveConfirmation(requiredHits: 1).confirm(now), isTrue);
    });

    test('requiredHits of 3 needs three', () {
      final c = GloveConfirmation(requiredHits: 3);
      expect(c.confirm(now), isFalse);
      expect(c.confirm(tick()), isFalse);
      expect(c.confirm(tick()), isTrue);
    });

    test('hits is observable for diagnostics', () {
      final c = GloveConfirmation();
      c.confirm(now);
      expect(c.hits, 1);
    });
  });

  test('replays the recorded false-positive run and suppresses every alarm', () {
    // Transcribed from the device log of 11 October 2026. Each entry is one
    // glove classification; `false` is NORMAL, which retracts and resets.
    final recorded = <(int, bool)>[
      (0, false), // 23:47:30 calm
      (1, true), //  23:47:31 FALL 0.96   <- fired critical
      (1, false), // 23:47:32 NORMAL
      (3, true), //  23:47:35 FALL 0.96   <- fired critical
      (1, false), // 23:47:36 NORMAL
      (3, true), //  23:47:39 FALL 0.92   <- fired critical
      (1, false), // 23:47:40 NORMAL, then 30+ s of calm
    ];

    final c = GloveConfirmation();
    var reported = 0;
    for (final (gap, threatening) in recorded) {
      tick(gap);
      if (threatening) {
        if (c.confirm(now)) reported++;
      } else {
        c.reset();
      }
    }

    expect(reported, 0,
        reason: 'all three spikes were isolated and must not reach fusion');
  });

  test('still reports a genuine fall from the same starting state', () {
    // What a real fall looks like on the same glove: consecutive windows.
    final c = GloveConfirmation();
    c.reset();
    expect(c.confirm(tick()), isFalse, reason: 'first window: look, do not alarm');
    expect(c.confirm(tick()), isTrue, reason: 'second window confirms it');
  });
}
