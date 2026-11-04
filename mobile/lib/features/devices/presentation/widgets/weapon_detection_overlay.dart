import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/weapon_overlay.dart';
import '../../domain/weapon_scorer.dart';

/// Draws the detector's boxes over the live video.
///
/// ## The coordinate problem this solves
///
/// A detection's box is a fraction of the *source frame*. The preview paints
/// that frame with `BoxFit.cover` into a 4:3 widget, and cover **crops**: when
/// the camera's aspect ratio differs from the widget's, part of the frame is
/// never on screen. Multiplying a normalised box by the widget's size — the
/// obvious implementation — therefore puts every box in the wrong place, and
/// wrongly by an amount that changes with the layout, so it looks almost right
/// on one phone and badly off on another.
///
/// The fix is to repeat the arithmetic `paintImage` does: [applyBoxFit] gives
/// the portion of the source actually used and the rectangle it is drawn into,
/// and a box is mapped from one to the other. That makes the overlay correct
/// under cover, contain, letterboxing and any widget size, and it is the
/// reason [fit] and [frameSize] are both required rather than assumed.
///
/// This is the same class of error that once made this model measure mAP 0.0
/// while being perfectly healthy: boxes in the wrong coordinate convention are
/// not obviously wrong, they are confidently and precisely wrong.
///
/// ## What this deliberately does not do: exact frame pairing
///
/// Boxes are drawn over whichever frame is on screen now, not over the frame
/// they were computed from. Inference runs at ~5 fps against a 10–15 fps
/// stream, so a box trails its own frame by up to one inference interval plus
/// the inference itself — on the order of 200 ms plus latency, unmeasured on
/// real hardware.
///
/// Pairing them exactly would mean holding each frame back until its inference
/// finished, which delays the video to improve the rectangle, on a screen
/// someone may be using to see what is behind her. The video is the safety
/// feature and the box is an annotation on it, so the lag is accepted and
/// written down rather than designed away. A fast pan will show it: the box
/// lags the weapon. That is the known cost.
class WeaponDetectionOverlay extends StatelessWidget {
  const WeaponDetectionOverlay({
    required this.detections,
    required this.frameSize,
    this.fit = BoxFit.cover,
    super.key,
  });

  /// What to draw. Already filtered by `WeaponOverlayState` for confidence,
  /// weapon class and a usable box.
  final List<WeaponDetection> detections;

  /// The source frame's pixel size. Without it the crop cannot be undone, so
  /// nothing is drawn — see [WeaponOverlayState.frameSize].
  final Size? frameSize;

  /// Must match the `BoxFit` the video underneath is painted with.
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final size = frameSize;
    if (size == null || detections.isEmpty) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      // Purely decorative: it must never swallow a tap meant for the video or
      // for a control underneath it.
      child: CustomPaint(
        painter: _WeaponBoxPainter(
          detections: detections,
          frameSize: size,
          fit: fit,
          textDirection: Directionality.of(context),
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// Maps a normalised box onto the widget, through the fit the video uses.
///
/// Pulled out of the painter so the arithmetic can be asserted directly. It is
/// the one part of this feature that is silently wrong when it is wrong: a box
/// drawn with the wrong mapping still looks like a confident detection, just
/// over the wrong part of the picture, and no amount of looking at a live
/// stream reliably catches a consistent offset. Tests pin it against hand-
/// computed rectangles for both cover and contain.
@immutable
class WeaponOverlayGeometry {
  const WeaponOverlayGeometry._({
    required this.source,
    required this.destination,
    required this.frameSize,
  });

  /// The part of the source frame that survives the fit. Under
  /// [BoxFit.cover] this is a crop; under [BoxFit.contain] it is the whole
  /// frame.
  final Rect source;

  /// Where that part is drawn inside the widget. Under [BoxFit.contain] this
  /// is letterboxed inside the widget; under [BoxFit.cover] it fills it.
  final Rect destination;

  final Size frameSize;

  /// Null when there is nothing sensible to map — a zero-area widget during
  /// layout, or a frame size the detector never reported.
  static WeaponOverlayGeometry? of({
    required Size frameSize,
    required Size widgetSize,
    required BoxFit fit,
  }) {
    if (widgetSize.isEmpty || frameSize.isEmpty) return null;
    // The same two rectangles `paintImage` computes, which is the point: the
    // overlay is correct precisely because it repeats the image's own
    // arithmetic rather than approximating it.
    final fitted = applyBoxFit(fit, frameSize, widgetSize);
    final source =
        Alignment.center.inscribe(fitted.source, Offset.zero & frameSize);
    final destination =
        Alignment.center.inscribe(fitted.destination, Offset.zero & widgetSize);
    if (source.isEmpty || destination.isEmpty) return null;
    return WeaponOverlayGeometry._(
      source: source,
      destination: destination,
      frameSize: frameSize,
    );
  }

  double get _scaleX => destination.width / source.width;
  double get _scaleY => destination.height / source.height;

  /// The on-screen rectangle for a box expressed as fractions of the frame.
  Rect rectFor(WeaponBox box) => Rect.fromLTRB(
        destination.left + (box.left * frameSize.width - source.left) * _scaleX,
        destination.top + (box.top * frameSize.height - source.top) * _scaleY,
        destination.left +
            (box.right * frameSize.width - source.left) * _scaleX,
        destination.top +
            (box.bottom * frameSize.height - source.top) * _scaleY,
      );
}

class _WeaponBoxPainter extends CustomPainter {
  _WeaponBoxPainter({
    required this.detections,
    required this.frameSize,
    required this.fit,
    required this.textDirection,
  });

  final List<WeaponDetection> detections;
  final Size frameSize;
  final BoxFit fit;
  final TextDirection textDirection;

  static const _strokeWidth = 2.5;
  static const _cornerRadius = Radius.circular(6);

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = WeaponOverlayGeometry.of(
      frameSize: frameSize,
      widgetSize: size,
      fit: fit,
    );
    if (geometry == null) return;

    // Anything cover cropped away is genuinely not on screen, so boxes are
    // clipped to the drawn image rather than to the widget: without this a
    // weapon just outside the visible crop would be drawn squashed against
    // the edge, pointing at a place the user cannot see.
    canvas.save();
    canvas.clipRect(geometry.destination);

    for (final detection in detections) {
      final box = detection.box;
      if (box == null || !box.isUsable) continue;

      final rect = geometry.rectFor(box);
      if (!rect.overlaps(geometry.destination)) continue;

      _paintBox(canvas, rect);
      _paintLabel(canvas, rect, geometry.destination, detection);
    }

    canvas.restore();
  }

  void _paintBox(Canvas canvas, Rect rect) {
    final rounded = RRect.fromRectAndRadius(rect, _cornerRadius);
    // A dark outer stroke under the bright one, so the box stays visible over
    // a pale background. A single-colour box disappears against a white wall,
    // which is a plausible place to be holding a knife.
    canvas.drawRRect(
      rounded,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth + 2
        ..color = const Color(0x66000000),
    );
    canvas.drawRRect(
      rounded,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..color = AppColors.coral400,
    );
  }

  void _paintLabel(
    Canvas canvas,
    Rect rect,
    Rect bounds,
    WeaponDetection detection,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: '${detection.label} '
            '${(detection.confidence * 100).round()}%',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
      textDirection: textDirection,
    )..layout();

    const padH = 6.0;
    const padV = 3.0;
    final chipWidth = painter.width + padH * 2;
    final chipHeight = painter.height + padV * 2;

    // Above the box by default; inside it when the box is hard against the
    // top edge, so the label is never clipped out of existence.
    var top = rect.top - chipHeight - 2;
    if (top < bounds.top) top = rect.top + 2;

    var left = rect.left;
    if (left + chipWidth > bounds.right) left = bounds.right - chipWidth;
    if (left < bounds.left) left = bounds.left;

    final chip = Rect.fromLTWH(left, top, chipWidth, chipHeight);
    canvas.drawRRect(
      RRect.fromRectAndRadius(chip, const Radius.circular(4)),
      Paint()..color = AppColors.coral500,
    );
    painter.paint(canvas, Offset(chip.left + padH, chip.top + padV));
  }

  @override
  bool shouldRepaint(_WeaponBoxPainter old) =>
      old.frameSize != frameSize ||
      old.fit != fit ||
      !identical(old.detections, detections);
}
