import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/safety/domain/camera_activation_policy.dart';

/// The camera no longer runs for the whole journey: the microphone and the
/// glove are cheap and always on, so they say when the expensive thing should
/// look. These pin that judgement — when it opens, how long it stays, and the
/// one case that is allowed to ignore the battery.
void main() {
  final t0 = DateTime.utc(2026, 9, 17, 21);

  CameraActivationPolicy build() => CameraActivationPolicy();

  group('opening', () {
    test('an elevated phrase opens the camera', () {
      final policy = build();
      expect(policy.reportAudio(0.6, now: t0), isTrue);
      expect(policy.isOpen, isTrue);
      expect(policy.openedBy, CameraTrigger.audio);
    });

    test('an ordinary phrase does not', () {
      final policy = build();
      expect(policy.reportAudio(0.49, now: t0), isFalse);
      expect(policy.isOpen, isFalse);
    });

    test('the glove opens it', () {
      final policy = build();
      expect(policy.reportGlove(0.7, now: t0), isTrue);
      expect(policy.openedBy, CameraTrigger.glove);
    });

    test('everyday movement does not', () {
      // SHAKING and TWISTING map to 0.3 — a hand dried, a jar opened.
      final policy = build();
      expect(policy.reportGlove(0.3, now: t0), isFalse);
      expect(policy.isOpen, isFalse);
    });
  });

  group('how long it stays open', () {
    test('closes once the dwell elapses', () {
      final policy = build()..reportAudio(0.9, now: t0);

      expect(policy.shouldClose(now: t0.add(const Duration(seconds: 29))), isFalse);
      expect(policy.shouldClose(now: t0.add(const Duration(seconds: 30))), isTrue);
    });

    test('the dwell outlasts the scorer evidence window', () {
      // The scorer votes over 15 frames at ~5 fps — about three seconds. A
      // dwell shorter than that would close the camera before any score it
      // produced could mean anything.
      final policy = build();
      expect(policy.dwell, greaterThan(const Duration(seconds: 3)));
    });

    test('a second trigger extends rather than restarts', () {
      final policy = build()..reportAudio(0.9, now: t0);
      final later = t0.add(const Duration(seconds: 20));

      policy.reportAudio(0.9, now: later);

      expect(policy.shouldClose(now: later.add(const Duration(seconds: 29))), isFalse);
      expect(policy.shouldClose(now: later.add(const Duration(seconds: 30))), isTrue);
    });

    test('still seeing something keeps it open', () {
      final policy = build()..reportGlove(0.8, now: t0);
      final later = t0.add(const Duration(seconds: 25));

      policy.reportWeapon(0.7, now: later);

      expect(policy.shouldClose(now: later.add(const Duration(seconds: 20))), isFalse);
      expect(policy.openedBy, CameraTrigger.weapon);
    });

    test('a weapon score cannot open a closed camera', () {
      // A closed camera produces no frames, so a score claiming otherwise is
      // about a picture nobody took.
      final policy = build()..reportWeapon(0.9, now: t0);
      expect(policy.isOpen, isFalse);
    });

    test('an opening that keeps extending still ends', () {
      var now = t0;
      final policy = build()..reportAudio(0.9, now: now);

      // Something in view, re-extending every 10 seconds for five minutes.
      for (var i = 0; i < 30; i++) {
        now = now.add(const Duration(seconds: 10));
        policy.reportWeapon(0.6, now: now);
      }

      expect(
        policy.shouldClose(now: now),
        isTrue,
        reason: 'maxOpen bounds a false trigger that keeps renewing itself',
      );
    });
  });

  group('cooldown', () {
    test('an ordinary trigger cannot reopen immediately', () {
      final policy = build()..reportAudio(0.9, now: t0);
      final closedAt = t0.add(const Duration(seconds: 30));
      policy.close(now: closedAt);

      expect(
        policy.reportAudio(0.9, now: closedAt.add(const Duration(seconds: 5))),
        isFalse,
        reason: 'cycling the camera costs more than leaving it open',
      );
    });

    test('and may once the cooldown passes', () {
      final policy = build()..reportAudio(0.9, now: t0);
      final closedAt = t0.add(const Duration(seconds: 30));
      policy.close(now: closedAt);

      expect(
        policy.reportAudio(0.9, now: closedAt.add(const Duration(seconds: 11))),
        isTrue,
      );
    });

    test('a confident fall ignores the cooldown', () {
      // The one signal describing something that has already gone wrong. Making
      // it wait out a battery timer is the wrong trade.
      final policy = build()..reportAudio(0.9, now: t0);
      final closedAt = t0.add(const Duration(seconds: 30));
      policy.close(now: closedAt);

      expect(
        policy.reportGlove(1.0, now: closedAt.add(const Duration(seconds: 1))),
        isTrue,
      );
      expect(policy.openedBy, CameraTrigger.glove);
    });

    test('a merely elevated glove reading does not', () {
      final policy = build()..reportAudio(0.9, now: t0);
      final closedAt = t0.add(const Duration(seconds: 30));
      policy.close(now: closedAt);

      expect(
        policy.reportGlove(0.7, now: closedAt.add(const Duration(seconds: 1))),
        isFalse,
      );
    });
  });

  group('lifecycle', () {
    test('closing clears the opening', () {
      final policy = build()..reportAudio(0.9, now: t0);
      policy.close(now: t0.add(const Duration(seconds: 30)));

      expect(policy.isOpen, isFalse);
      expect(policy.openedBy, isNull);
      expect(policy.closesAt, isNull);
    });

    test('closing an already closed camera is harmless', () {
      final policy = build();
      expect(() => policy.close(now: t0), returnsNormally);
      expect(policy.isOpen, isFalse);
    });

    test('reset clears the cooldown too, so a new journey starts clean', () {
      final policy = build()..reportAudio(0.9, now: t0);
      final closedAt = t0.add(const Duration(seconds: 30));
      policy.close(now: closedAt);

      policy.reset();

      expect(
        policy.reportAudio(0.9, now: closedAt.add(const Duration(seconds: 1))),
        isTrue,
        reason: 'the next journey must not begin inside the last one\'s timers',
      );
    });

    test('shouldClose is false while nothing is open', () {
      expect(build().shouldClose(now: t0), isFalse);
    });
  });
}
