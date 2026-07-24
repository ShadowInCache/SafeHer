import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_extensions.dart';

/// Circular progress stroke with a label centered inside the ring (e.g. a
/// weekly safety score, a countdown).
class SaProgressRing extends StatelessWidget {
  const SaProgressRing({
    required this.progress,
    super.key,
    this.size = 80,
    this.strokeWidth = 8,
    this.label,
    this.color = AppColors.violet500,
  });

  /// 0.0–1.0
  final double progress;
  final double size;
  final double strokeWidth;
  final String? label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: 'Progress ${(progress.clamp(0.0, 1.0) * 100).round()} percent',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: _RingPainter(
                progress: progress.clamp(0.0, 1.0),
                strokeWidth: strokeWidth,
                trackColor: saColors.surfaceHighest,
                color: color,
              ),
            ),
            if (label != null)
              Text(label!, style: AppTypography.headingS.copyWith(color: onSurface)),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.strokeWidth, required this.trackColor, required this.color});

  final double progress;
  final double strokeWidth;
  final Color trackColor;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(rect, 0, 2 * 3.14159265, false, track);

    if (progress <= 0) return;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -3.14159265 / 2, 2 * 3.14159265 * progress, false, fill);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
