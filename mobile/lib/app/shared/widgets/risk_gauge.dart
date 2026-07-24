import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/premium_theme.dart';

class RiskGauge extends StatelessWidget {
  final double score;
  final double size;

  const RiskGauge({super.key, required this.score, this.size = 150});

  @override
  Widget build(BuildContext context) {
    final clamped = score.clamp(0, 100).toDouble();
    return SizedBox(
      height: size,
      width: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: clamped / 100),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) {
          return CustomPaint(
            painter: _RiskGaugePainter(value),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    clamped.toStringAsFixed(0),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text(
                    'Threat Score',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RiskGaugePainter extends CustomPainter {
  final double value;

  _RiskGaugePainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;

    final backgroundPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final foregroundPaint = Paint()
      ..shader = SweepGradient(
        colors: const [
          PremiumTheme.safe,
          PremiumTheme.warning,
          PremiumTheme.danger,
        ],
        startAngle: -math.pi / 2,
        endAngle: (3 * math.pi) / 2,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2,
      false,
      backgroundPaint,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      (math.pi * 2) * value,
      false,
      foregroundPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RiskGaugePainter oldDelegate) {
    return oldDelegate.value != value;
  }
}
