import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/domain/weapon_overlay.dart';
import 'package:safeher_app/features/devices/domain/weapon_scorer.dart';

/// The rules that decide what is on screen.
///
/// These are deliberately separate from `weapon_scorer_test.dart`: the scorer
/// decides what may raise an alarm and this decides what may be drawn, and the
/// two are allowed to disagree. Several tests below exist specifically to pin
/// that disagreement, because collapsing the two rules into one is the obvious
/// "simplification" a future reader would attempt.
void main() {
  final at = DateTime(2026, 11, 4, 12);
  const frame = Size(640, 480);

  WeaponDetection detection({
    String label = 'knife',
    double confidence = 0.80,
    WeaponBox? box = const WeaponBox(left: 0.1, top: 0.1, right: 0.4, bottom: 0.5),
    DateTime? when,
  }) =>
      WeaponDetection(
        label: label,
        confidence: confidence,
        at: when ?? at,
        box: box,
      );

  group('what gets drawn', () {
    test('a confident weapon with a box is drawn', () {
      final state = const WeaponOverlayState()
          .withFrame([detection()], at: at, frameSize: frame);

      expect(state.visibleAt(at), hasLength(1));
      expect(state.visibleAt(at).single.label, 'knife');
      expect(state.frameSize, frame);
    });

    test('multiple detections in one frame each survive', () {
      final state = const WeaponOverlayState().withFrame([
        detection(label: 'knife'),
        detection(
          label: 'pistol',
          box: const WeaponBox(left: 0.5, top: 0.2, right: 0.9, bottom: 0.7),
        ),
      ], at: at, frameSize: frame);

      expect(
        state.visibleAt(at).map((d) => d.label),
        containsAll(<String>['knife', 'pistol']),
      );
    });

    test('a detection below the draw threshold is not drawn', () {
      final state = const WeaponOverlayState()
          .withFrame([detection(confidence: 0.20)], at: at, frameSize: frame);

      expect(state.visibleAt(at), isEmpty);
    });

    test('the draw threshold is the detector floor, not the scorer floor', () {
      // 0.40 sits between the two on purpose: above the detector's 0.35
      // reporting threshold, below the scorer's 0.55 alarm floor. It must be
      // drawn -- a weak detection is informative *because* it is visibly weak,
      // and hiding it would make the model look more certain than it is.
      final state = const WeaponOverlayState()
          .withFrame([detection(confidence: 0.40)], at: at, frameSize: frame);

      expect(state.visibleAt(at), hasLength(1));
      expect(
        WeaponOverlayState.defaultDrawThreshold,
        lessThan(WeaponScorer().confidenceFloor),
        reason: 'the overlay must show more than the alarm acts on',
      );
    });

    test('a non-weapon class from the 6-class model is never drawn', () {
      // Drawing "smartphone 0.91" over a live video would be worse than
      // drawing nothing: the distractor classes exist to be rejected, and a
      // box around a phone reads as a weapon alert to anyone glancing at it.
      final state = const WeaponOverlayState()
          .withFrame([detection(label: 'smartphone')], at: at, frameSize: frame);

      expect(state.visibleAt(at), isEmpty);
    });

    test('a detection with no box reaches the scorer but not the screen', () {
      // This is the server path, which returns a label and a confidence and no
      // coordinates. It is a real detection and it must not be drawn, because
      // there is nowhere truthful to draw it.
      final state = const WeaponOverlayState()
          .withFrame([detection(box: null)], at: at, frameSize: frame);

      expect(state.visibleAt(at), isEmpty);
    });

    test('a zero-area box is rejected rather than painted as a line', () {
      final state = const WeaponOverlayState().withFrame([
        detection(
          box: const WeaponBox(left: 0.4, top: 0.4, right: 0.4, bottom: 0.8),
        ),
      ], at: at, frameSize: frame);

      expect(state.visibleAt(at), isEmpty);
    });
  });

  group('boxes come down again', () {
    test('a result is held while it is fresh', () {
      final state = const WeaponOverlayState()
          .withFrame([detection()], at: at, frameSize: frame);

      // Half a second later, with no newer inference: still drawn, which is
      // what stops the box blinking between the 5 fps inference and the
      // 10-15 fps video.
      expect(
        state.visibleAt(at.add(const Duration(milliseconds: 500))),
        hasLength(1),
      );
      expect(state.isStaleAt(at.add(const Duration(milliseconds: 500))), isFalse);
    });

    test('a result older than staleAfter is dropped', () {
      final state = const WeaponOverlayState()
          .withFrame([detection()], at: at, frameSize: frame);

      final later = at.add(const Duration(milliseconds: 1500));
      expect(state.visibleAt(later), isEmpty);
      expect(state.isStaleAt(later), isTrue);
    });

    test('an inference that found nothing takes the boxes down immediately',
        () {
      // Not the same as going stale. The detector looked at this frame and the
      // weapon was gone, so the box must not linger for another second.
      final seen = const WeaponOverlayState()
          .withFrame([detection()], at: at, frameSize: frame);
      final then = seen.withFrame(const [], at: at, frameSize: frame);

      expect(then.visibleAt(at), isEmpty);
      expect(then.isStaleAt(at), isFalse,
          reason: 'it is current, it simply contains nothing');
    });

    test('clearing takes the boxes down without waiting to go stale', () {
      final state = const WeaponOverlayState()
          .withFrame([detection()], at: at, frameSize: frame);

      expect(state.cleared().visibleAt(at), isEmpty);
    });

    test('nothing is drawn before the first inference', () {
      expect(const WeaponOverlayState().visibleAt(at), isEmpty);
      expect(const WeaponOverlayState().isStaleAt(at), isFalse,
          reason: 'never having run is not the same as having gone quiet');
    });

    test('a later frame replaces an earlier one rather than adding to it', () {
      final first = const WeaponOverlayState()
          .withFrame([detection(label: 'knife')], at: at, frameSize: frame);
      final second = first.withFrame(
        [detection(label: 'pistol')],
        at: at.add(const Duration(milliseconds: 200)),
        frameSize: frame,
      );

      final visible = second.visibleAt(at.add(const Duration(milliseconds: 200)));
      expect(visible, hasLength(1));
      expect(visible.single.label, 'pistol');
    });

    test('a frame size once known survives a frame that omits it', () {
      // The plugin reports imageSize on every successful inference, but a
      // detector that stops reporting it must not blank the overlay: without a
      // frame size nothing can be drawn at all.
      final state = const WeaponOverlayState()
          .withFrame([detection()], at: at, frameSize: frame)
          .withFrame([detection()], at: at, frameSize: null);

      expect(state.frameSize, frame);
    });
  });

  group('thresholds are configurable', () {
    test('a stricter draw threshold hides a weak detection', () {
      const strict = WeaponOverlayState(drawThreshold: 0.90);

      expect(
        strict.withFrame([detection(confidence: 0.80)], at: at).visibleAt(at),
        isEmpty,
      );
    });

    test('a longer hold keeps a box past the default expiry', () {
      const patient = WeaponOverlayState(staleAfter: Duration(seconds: 5));
      final state = patient.withFrame([detection()], at: at, frameSize: frame);

      expect(
        state.visibleAt(at.add(const Duration(seconds: 3))),
        hasLength(1),
      );
    });
  });
}
