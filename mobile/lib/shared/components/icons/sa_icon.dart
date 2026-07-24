import 'package:flutter/widgets.dart';

/// Custom vector glyphs used throughout SafeHer instead of Material's
/// default icon set. New glyphs are added here as screens need them.
enum SaIconGlyph {
  shield,
  bell,
  chevronRight,
  chevronLeft,
  close,
  check,
  search,
  mic,
  home,
  monitorPulse,
  dashboard,
  profile,
  eye,
  eyeOff,
  battery,
  signal,
  camera,
  mapPin,
}

/// Renders a [SaIconGlyph] via [CustomPainter] — a hand-drawn vector icon,
/// not a Material [Icon] glyph, per the design system's icon rule.
class SaIcon extends StatelessWidget {
  const SaIcon(this.glyph, {super.key, this.size = 24, this.color, this.strokeWidth = 2.0});

  final SaIconGlyph glyph;
  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? IconTheme.of(context).color ?? const Color(0xFF18181B);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size.square(size),
        painter: _SaIconPainter(glyph, resolvedColor, strokeWidth),
      ),
    );
  }
}

class _SaIconPainter extends CustomPainter {
  _SaIconPainter(this.glyph, this.color, this.strokeWidth);

  final SaIconGlyph glyph;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (glyph) {
      case SaIconGlyph.shield:
        _paintShield(canvas, size, stroke);
      case SaIconGlyph.bell:
        _paintBell(canvas, size, stroke);
      case SaIconGlyph.chevronRight:
        _paintChevron(canvas, size, stroke, pointRight: true);
      case SaIconGlyph.chevronLeft:
        _paintChevron(canvas, size, stroke, pointRight: false);
      case SaIconGlyph.close:
        _paintClose(canvas, size, stroke);
      case SaIconGlyph.check:
        _paintCheck(canvas, size, stroke);
      case SaIconGlyph.search:
        _paintSearch(canvas, size, stroke);
      case SaIconGlyph.mic:
        _paintMic(canvas, size, stroke, fill);
      case SaIconGlyph.home:
        _paintHome(canvas, size, stroke);
      case SaIconGlyph.monitorPulse:
        _paintMonitorPulse(canvas, size, stroke);
      case SaIconGlyph.dashboard:
        _paintDashboard(canvas, size, fill);
      case SaIconGlyph.profile:
        _paintProfile(canvas, size, stroke, fill);
      case SaIconGlyph.eye:
        _paintEye(canvas, size, stroke, fill);
      case SaIconGlyph.eyeOff:
        _paintEyeOff(canvas, size, stroke, fill);
      case SaIconGlyph.battery:
        _paintBattery(canvas, size, stroke);
      case SaIconGlyph.signal:
        _paintSignal(canvas, size, fill);
      case SaIconGlyph.camera:
        _paintCamera(canvas, size, stroke);
      case SaIconGlyph.mapPin:
        _paintMapPin(canvas, size, stroke, fill);
    }
  }

  void _paintShield(Canvas canvas, Size size, Paint stroke) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, h * 0.05)
      ..lineTo(w * 0.88, h * 0.2)
      ..lineTo(w * 0.88, h * 0.5)
      ..cubicTo(w * 0.88, h * 0.75, w * 0.7, h * 0.92, w * 0.5, h * 0.97)
      ..cubicTo(w * 0.3, h * 0.92, w * 0.12, h * 0.75, w * 0.12, h * 0.5)
      ..lineTo(w * 0.12, h * 0.2)
      ..close();
    canvas.drawPath(path, stroke);
    final checkPath = Path()
      ..moveTo(w * 0.34, h * 0.5)
      ..lineTo(w * 0.46, h * 0.62)
      ..lineTo(w * 0.68, h * 0.38);
    canvas.drawPath(checkPath, stroke);
  }

  void _paintBell(Canvas canvas, Size size, Paint stroke) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.28, h * 0.75)
      ..lineTo(w * 0.72, h * 0.75)
      ..lineTo(w * 0.68, h * 0.68)
      ..lineTo(w * 0.68, h * 0.4)
      ..cubicTo(w * 0.68, h * 0.24, w * 0.58, h * 0.14, w * 0.5, h * 0.14)
      ..cubicTo(w * 0.42, h * 0.14, w * 0.32, h * 0.24, w * 0.32, h * 0.4)
      ..lineTo(w * 0.32, h * 0.68)
      ..close();
    canvas.drawPath(path, stroke);
    canvas.drawArc(Rect.fromCenter(center: Offset(w * 0.5, h * 0.8), width: w * 0.18, height: h * 0.12), 0, 3.14, false, stroke);
  }

  void _paintChevron(Canvas canvas, Size size, Paint stroke, {required bool pointRight}) {
    final w = size.width, h = size.height;
    final path = Path();
    if (pointRight) {
      path
        ..moveTo(w * 0.36, h * 0.2)
        ..lineTo(w * 0.68, h * 0.5)
        ..lineTo(w * 0.36, h * 0.8);
    } else {
      path
        ..moveTo(w * 0.64, h * 0.2)
        ..lineTo(w * 0.32, h * 0.5)
        ..lineTo(w * 0.64, h * 0.8);
    }
    canvas.drawPath(path, stroke);
  }

  void _paintClose(Canvas canvas, Size size, Paint stroke) {
    final w = size.width, h = size.height;
    canvas.drawLine(Offset(w * 0.25, h * 0.25), Offset(w * 0.75, h * 0.75), stroke);
    canvas.drawLine(Offset(w * 0.75, h * 0.25), Offset(w * 0.25, h * 0.75), stroke);
  }

  void _paintCheck(Canvas canvas, Size size, Paint stroke) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.2, h * 0.52)
      ..lineTo(w * 0.42, h * 0.72)
      ..lineTo(w * 0.8, h * 0.28);
    canvas.drawPath(path, stroke);
  }

  void _paintSearch(Canvas canvas, Size size, Paint stroke) {
    final w = size.width, h = size.height;
    canvas.drawCircle(Offset(w * 0.44, h * 0.44), w * 0.26, stroke);
    canvas.drawLine(Offset(w * 0.64, h * 0.64), Offset(w * 0.84, h * 0.84), stroke);
  }

  void _paintMic(Canvas canvas, Size size, Paint stroke, Paint fill) {
    final w = size.width, h = size.height;
    final capsule = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.38), width: w * 0.28, height: h * 0.44),
      Radius.circular(w * 0.14),
    );
    canvas.drawRRect(capsule, stroke);
    canvas.drawArc(Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w * 0.56, height: h * 0.56), 0.3, 2.6, false, stroke);
    canvas.drawLine(Offset(w * 0.5, h * 0.78), Offset(w * 0.5, h * 0.92), stroke);
    canvas.drawLine(Offset(w * 0.34, h * 0.92), Offset(w * 0.66, h * 0.92), stroke);
  }

  void _paintHome(Canvas canvas, Size size, Paint stroke) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.15, h * 0.5)
      ..lineTo(w * 0.5, h * 0.15)
      ..lineTo(w * 0.85, h * 0.5)
      ..moveTo(w * 0.25, h * 0.42)
      ..lineTo(w * 0.25, h * 0.85)
      ..lineTo(w * 0.75, h * 0.85)
      ..lineTo(w * 0.75, h * 0.42);
    canvas.drawPath(path, stroke);
  }

  void _paintMonitorPulse(Canvas canvas, Size size, Paint stroke) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.1, h * 0.55)
      ..lineTo(w * 0.32, h * 0.55)
      ..lineTo(w * 0.42, h * 0.25)
      ..lineTo(w * 0.58, h * 0.75)
      ..lineTo(w * 0.68, h * 0.55)
      ..lineTo(w * 0.9, h * 0.55);
    canvas.drawPath(path, stroke);
  }

  void _paintDashboard(Canvas canvas, Size size, Paint fill) {
    final w = size.width, h = size.height;
    const gap = 0.08;
    void block(double x, double y, double bw, double bh) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(w * x, h * y, w * bw, h * bh), Radius.circular(w * 0.06)),
        fill,
      );
    }

    block(0.12, 0.12, 0.34, 0.34);
    block(0.54, 0.12, 0.34, 0.2);
    block(0.54, 0.4 + gap, 0.34, 0.2 - gap);
    block(0.12, 0.54, 0.76, 0.34);
  }

  void _paintProfile(Canvas canvas, Size size, Paint stroke, Paint fill) {
    final w = size.width, h = size.height;
    canvas.drawCircle(Offset(w * 0.5, h * 0.34), w * 0.16, stroke);
    final path = Path()
      ..moveTo(w * 0.2, h * 0.86)
      ..cubicTo(w * 0.2, h * 0.62, w * 0.34, h * 0.54, w * 0.5, h * 0.54)
      ..cubicTo(w * 0.66, h * 0.54, w * 0.8, h * 0.62, w * 0.8, h * 0.86);
    canvas.drawPath(path, stroke);
  }

  void _paintEye(Canvas canvas, Size size, Paint stroke, Paint fill) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.1, h * 0.5)
      ..cubicTo(w * 0.25, h * 0.25, w * 0.75, h * 0.25, w * 0.9, h * 0.5)
      ..cubicTo(w * 0.75, h * 0.75, w * 0.25, h * 0.75, w * 0.1, h * 0.5)
      ..close();
    canvas.drawPath(path, stroke);
    canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.11, fill);
  }

  void _paintEyeOff(Canvas canvas, Size size, Paint stroke, Paint fill) {
    _paintEye(canvas, size, stroke, fill);
    canvas.drawLine(Offset(size.width * 0.16, size.height * 0.18), Offset(size.width * 0.84, size.height * 0.82), stroke);
  }

  void _paintBattery(Canvas canvas, Size size, Paint stroke) {
    final w = size.width, h = size.height;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.1, h * 0.28, w * 0.72, h * 0.44), Radius.circular(w * 0.06)),
      stroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.84, h * 0.4, w * 0.08, h * 0.2), Radius.circular(w * 0.02)),
      stroke..style = PaintingStyle.fill,
    );
  }

  void _paintSignal(Canvas canvas, Size size, Paint fill) {
    final w = size.width, h = size.height;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.1, h * 0.62, w * 0.18, h * 0.28), Radius.circular(w * 0.03)), fill);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.41, h * 0.4, w * 0.18, h * 0.5), Radius.circular(w * 0.03)), fill);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.72, h * 0.14, w * 0.18, h * 0.76), Radius.circular(w * 0.03)), fill);
  }

  void _paintCamera(Canvas canvas, Size size, Paint stroke) {
    final w = size.width, h = size.height;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.1, h * 0.28, w * 0.8, h * 0.56), Radius.circular(w * 0.08)),
      stroke,
    );
    canvas.drawCircle(Offset(w * 0.5, h * 0.56), w * 0.18, stroke);
    final lens = Path()
      ..moveTo(w * 0.36, h * 0.28)
      ..lineTo(w * 0.42, h * 0.16)
      ..lineTo(w * 0.58, h * 0.16)
      ..lineTo(w * 0.64, h * 0.28);
    canvas.drawPath(lens, stroke);
  }

  void _paintMapPin(Canvas canvas, Size size, Paint stroke, Paint fill) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, h * 0.92)
      ..cubicTo(w * 0.5, h * 0.92, w * 0.82, h * 0.58, w * 0.82, h * 0.38)
      ..cubicTo(w * 0.82, h * 0.2, w * 0.68, h * 0.08, w * 0.5, h * 0.08)
      ..cubicTo(w * 0.32, h * 0.08, w * 0.18, h * 0.2, w * 0.18, h * 0.38)
      ..cubicTo(w * 0.18, h * 0.58, w * 0.5, h * 0.92, w * 0.5, h * 0.92)
      ..close();
    canvas.drawPath(path, stroke);
    canvas.drawCircle(Offset(w * 0.5, h * 0.38), w * 0.1, fill);
  }

  @override
  bool shouldRepaint(covariant _SaIconPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
