import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/animations/animation_helpers.dart';
import '../../../core/theme/app_typography.dart';

class SaDonutSegment {
  const SaDonutSegment({required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;
}

/// Ring chart where each [segments] slice sweeps in sequentially (400ms per
/// segment) rather than all at once.
class SaDonutChart extends StatefulWidget {
  const SaDonutChart({required this.segments, super.key, this.size = 160, this.strokeWidth = 20});

  final List<SaDonutSegment> segments;
  final double size;
  final double strokeWidth;

  @override
  State<SaDonutChart> createState() => _SaDonutChartState();
}

class _SaDonutChartState extends State<SaDonutChart> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 400 * math.max(widget.segments.length, 1)),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => AnimationHelpers.forward(context, _controller));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final total = widget.segments.fold<double>(0, (sum, s) => sum + s.value);

    return Semantics(
      label: 'Donut chart with ${widget.segments.length} segments',
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: Size.square(widget.size),
                    painter: _DonutPainter(
                      segments: widget.segments,
                      total: total == 0 ? 1 : total,
                      progress: _controller.value,
                      strokeWidth: widget.strokeWidth,
                    ),
                  ),
                  Text('${widget.segments.length}', style: AppTypography.headingM.copyWith(color: onSurface)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.segments, required this.total, required this.progress, required this.strokeWidth});

  final List<SaDonutSegment> segments;
  final double total;
  final double progress;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    var startAngle = -math.pi / 2;
    final n = segments.length;
    for (var i = 0; i < n; i++) {
      final fullSweep = 2 * math.pi * (segments[i].value / total);
      final segmentStart = i / n;
      final segmentEnd = (i + 1) / n;
      final segmentProgress = ((progress - segmentStart) / (segmentEnd - segmentStart)).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = segments[i].color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, startAngle, fullSweep * segmentProgress, false, paint);
      startAngle += fullSweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => oldDelegate.progress != progress;
}
