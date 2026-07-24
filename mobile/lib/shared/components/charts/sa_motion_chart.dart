import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class MotionSample {
  const MotionSample({required this.x, required this.y, required this.z});

  final double x;
  final double y;
  final double z;
}

class MotionEventPin {
  const MotionEventPin({required this.sampleIndex, required this.label, required this.timestamp});

  final int sampleIndex;
  final String label;
  final String timestamp;
}

/// Scrolling 3-axis (X/Y/Z) accelerometer sparkline with tappable event
/// pins marking AI-detected moments.
class SaMotionChart extends StatelessWidget {
  const SaMotionChart({
    required this.samples,
    super.key,
    this.events = const [],
    this.height = 120,
    this.onPinTap,
  });

  final List<MotionSample> samples;
  final List<MotionEventPin> events;
  final double height;
  final ValueChanged<MotionEventPin>? onPinTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Motion timeline, ${events.length} detected events',
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, height);
            return GestureDetector(
              onTapUp: (details) {
                if (onPinTap == null || samples.isEmpty) return;
                final stepX = size.width / (samples.length - 1).clamp(1, double.infinity);
                for (final pin in events) {
                  final pinX = pin.sampleIndex * stepX;
                  if ((details.localPosition.dx - pinX).abs() < 12) {
                    onPinTap!(pin);
                    return;
                  }
                }
              },
              child: CustomPaint(
                size: size,
                painter: _MotionChartPainter(samples: samples, events: events),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MotionChartPainter extends CustomPainter {
  _MotionChartPainter({required this.samples, required this.events});

  final List<MotionSample> samples;
  final List<MotionEventPin> events;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;

    final allValues = samples.expand((s) => [s.x, s.y, s.z]).toList();
    final minV = allValues.reduce((a, b) => a < b ? a : b);
    final maxV = allValues.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 0.001 ? 1.0 : maxV - minV;
    final stepX = size.width / (samples.length - 1);

    double yFor(double v) => size.height - ((v - minV) / range) * size.height;

    void drawAxis(Color color, double Function(MotionSample) selector) {
      final path = Path();
      for (var i = 0; i < samples.length; i++) {
        final point = Offset(i * stepX, yFor(selector(samples[i])));
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
    }

    drawAxis(AppColors.violet500, (s) => s.x);
    drawAxis(AppColors.success500, (s) => s.y);
    drawAxis(AppColors.coral500, (s) => s.z);

    final pinPaint = Paint()
      ..color = AppColors.warning500
      ..strokeWidth = 1.5;
    for (final pin in events) {
      final x = pin.sampleIndex * stepX;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), pinPaint);
      canvas.drawCircle(Offset(x, 4), 3, Paint()..color = AppColors.warning500);
    }
  }

  @override
  bool shouldRepaint(covariant _MotionChartPainter oldDelegate) =>
      oldDelegate.samples != samples || oldDelegate.events != events;
}
