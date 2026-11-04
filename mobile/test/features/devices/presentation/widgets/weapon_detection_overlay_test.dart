import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/domain/weapon_scorer.dart';
import 'package:safeher_app/features/devices/presentation/widgets/weapon_detection_overlay.dart';

/// Where the boxes land.
///
/// This is the part of the overlay that is silently wrong when it is wrong. A
/// box drawn through the wrong mapping still looks like a confident detection;
/// it is simply over the wrong part of the picture, by an amount that depends
/// on the device's aspect ratio. Watching a live stream does not reliably catch
/// that, so the arithmetic is pinned here against hand-computed rectangles.
void main() {
  // 16:9 camera into a 4:3 preview box. Chosen because the aspect ratios
  // differ: with matching ratios every mapping agrees and the tests would pass
  // against a broken implementation.
  const frame = Size(640, 360);
  const widget = Size(300, 225);

  group('BoxFit.cover crops, and the mapping accounts for it', () {
    test('a box maps to its hand-computed rectangle', () {
      // cover scale = max(300/640, 225/360) = 0.625
      // source used = 480x360, centred in 640x360 -> left 80
      // dest = the whole 300x225 widget, scale 0.625
      final geometry = WeaponOverlayGeometry.of(
        frameSize: frame,
        widgetSize: widget,
        fit: BoxFit.cover,
      )!;

      expect(geometry.source, const Rect.fromLTRB(80, 0, 560, 360));
      expect(geometry.destination, const Rect.fromLTRB(0, 0, 300, 225));

      final rect = geometry.rectFor(
        const WeaponBox(left: 0.5, top: 0.5, right: 0.75, bottom: 0.75),
      );

      // src px (320,180,480,270) -> (x-80)*0.625, y*0.625
      expect(rect.left, closeTo(150, 0.001));
      expect(rect.top, closeTo(112.5, 0.001));
      expect(rect.right, closeTo(250, 0.001));
      expect(rect.bottom, closeTo(168.75, 0.001));
    });

    test('the naive mapping would fail this, which is why it is tested', () {
      // The obvious implementation -- multiply the normalised box by the
      // widget size -- gives 225 for this edge where the correct answer is
      // 250. The gap is the crop. If this expectation ever stops holding,
      // the test above has stopped discriminating and is worth nothing.
      final geometry = WeaponOverlayGeometry.of(
        frameSize: frame,
        widgetSize: widget,
        fit: BoxFit.cover,
      )!;
      final rect = geometry.rectFor(
        const WeaponBox(left: 0.5, top: 0.5, right: 0.75, bottom: 0.75),
      );
      const naiveRight = 0.75 * 300;

      expect(rect.right, isNot(closeTo(naiveRight, 1)));
    });

    test('a box cropped off the edge maps outside the widget, not onto it', () {
      // A weapon in the part of the frame cover threw away must not be drawn
      // squashed against the edge, pointing at somewhere the user cannot see.
      // The painter clips it; the mapping has to put it out of bounds first.
      final geometry = WeaponOverlayGeometry.of(
        frameSize: frame,
        widgetSize: widget,
        fit: BoxFit.cover,
      )!;

      final rect = geometry.rectFor(
        const WeaponBox(left: 0.0, top: 0.2, right: 0.05, bottom: 0.6),
      );

      expect(rect.right, lessThan(0),
          reason: 'entirely within the cropped-away strip');
    });
  });

  group('BoxFit.contain letterboxes, and the mapping accounts for that too', () {
    test('a box maps into the letterboxed rectangle', () {
      // contain scale = min(300/640, 225/360) = 0.46875
      // dest = 300x168.75, centred in 225 -> top 28.125
      final geometry = WeaponOverlayGeometry.of(
        frameSize: frame,
        widgetSize: widget,
        fit: BoxFit.contain,
      )!;

      expect(geometry.source, const Rect.fromLTRB(0, 0, 640, 360));
      expect(geometry.destination.top, closeTo(28.125, 0.001));
      expect(geometry.destination.bottom, closeTo(196.875, 0.001));

      final rect = geometry.rectFor(
        const WeaponBox(left: 0.5, top: 0.5, right: 0.75, bottom: 0.75),
      );

      expect(rect.left, closeTo(150, 0.001));
      expect(rect.top, closeTo(112.5, 0.001));
      expect(rect.right, closeTo(225, 0.001));
      expect(rect.bottom, closeTo(154.6875, 0.001));
    });
  });

  group('resizing', () {
    test('the same box keeps its proportions when the widget grows', () {
      const box = WeaponBox(left: 0.25, top: 0.25, right: 0.6, bottom: 0.8);

      final small = WeaponOverlayGeometry.of(
        frameSize: frame,
        widgetSize: const Size(300, 225),
        fit: BoxFit.cover,
      )!
          .rectFor(box);
      final large = WeaponOverlayGeometry.of(
        frameSize: frame,
        widgetSize: const Size(600, 450),
        fit: BoxFit.cover,
      )!
          .rectFor(box);

      // Exactly double, because the widget doubled and the fit is unchanged.
      expect(large.left, closeTo(small.left * 2, 0.001));
      expect(large.top, closeTo(small.top * 2, 0.001));
      expect(large.width, closeTo(small.width * 2, 0.001));
      expect(large.height, closeTo(small.height * 2, 0.001));
    });

    test('a portrait widget does not distort the box', () {
      // The box's aspect ratio on screen must match its aspect ratio in the
      // frame under cover, whatever shape the widget is -- cover scales both
      // axes equally and only crops.
      const box = WeaponBox(left: 0.3, top: 0.3, right: 0.5, bottom: 0.5);
      final geometry = WeaponOverlayGeometry.of(
        frameSize: frame,
        widgetSize: const Size(200, 400),
        fit: BoxFit.cover,
      )!;
      final rect = geometry.rectFor(box);

      final inFrame = (box.width * frame.width) / (box.height * frame.height);
      expect(rect.width / rect.height, closeTo(inFrame, 0.001));
    });
  });

  group('degenerate inputs', () {
    test('a zero-sized widget yields no geometry rather than a divide by zero',
        () {
      expect(
        WeaponOverlayGeometry.of(
          frameSize: frame,
          widgetSize: Size.zero,
          fit: BoxFit.cover,
        ),
        isNull,
      );
    });

    test('a zero-sized frame yields no geometry', () {
      expect(
        WeaponOverlayGeometry.of(
          frameSize: Size.zero,
          widgetSize: widget,
          fit: BoxFit.cover,
        ),
        isNull,
      );
    });
  });

  // Scoped to the overlay's own subtree: `Scaffold` and `MaterialApp` build
  // CustomPaints of their own, so a bare `find.byType(CustomPaint)` is true
  // whether or not the overlay drew anything.
  final overlayPainters = find.descendant(
    of: find.byType(WeaponDetectionOverlay),
    matching: find.byType(CustomPaint),
  );

  group('the widget itself', () {
    Widget host(Widget child) => MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 300, height: 225, child: child),
          ),
        );

    testWidgets('draws nothing when the frame size is unknown', (tester) async {
      // The server path reports no frame size. Drawing anyway would mean
      // guessing the aspect ratio, and a guessed box is worse than none.
      await tester.pumpWidget(host(
        WeaponDetectionOverlay(
          detections: [
            WeaponDetection(
              label: 'knife',
              confidence: 0.9,
              at: DateTime(2026, 11, 4),
              box: const WeaponBox(left: 0.1, top: 0.1, right: 0.4, bottom: 0.5),
            ),
          ],
          frameSize: null,
        ),
      ));

      expect(overlayPainters, findsNothing);
    });

    testWidgets('draws nothing when there are no detections', (tester) async {
      await tester.pumpWidget(host(
        const WeaponDetectionOverlay(detections: [], frameSize: frame),
      ));

      expect(overlayPainters, findsNothing);
    });

    testWidgets('paints when there is something to paint', (tester) async {
      await tester.pumpWidget(host(
        WeaponDetectionOverlay(
          detections: [
            WeaponDetection(
              label: 'knife',
              confidence: 0.9,
              at: DateTime(2026, 11, 4),
              box: const WeaponBox(left: 0.1, top: 0.1, right: 0.4, bottom: 0.5),
            ),
          ],
          frameSize: frame,
        ),
      ));

      expect(overlayPainters, findsOneWidget);
    });

    testWidgets('never swallows a tap meant for what is underneath',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(host(
        Stack(
          children: [
            GestureDetector(
              onTap: () => tapped = true,
              child: const SizedBox.expand(
                child: ColoredBox(color: Color(0xFF000000)),
              ),
            ),
            WeaponDetectionOverlay(
              detections: [
                WeaponDetection(
                  label: 'knife',
                  confidence: 0.9,
                  at: DateTime(2026, 11, 4),
                  box: const WeaponBox(
                      left: 0.0, top: 0.0, right: 1.0, bottom: 1.0),
                ),
              ],
              frameSize: frame,
            ),
          ],
        ),
      ));

      await tester.tapAt(const Offset(150, 112));
      expect(tapped, isTrue);
    });
  });
}
