import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../models/threat_level.dart';

/// 0°–270° arc gauge showing the current threat [score] (0.0–1.0) with a
/// spring-animated needle, 4 colour zones matching [ThreatLevel] bands, and
/// a center readout that counts up/down to the new value.
class SaThreatGauge extends StatefulWidget {
  const SaThreatGauge({required this.score, super.key, this.size = 200});

  final double score;
  final double size;

  @override
  State<SaThreatGauge> createState() => _SaThreatGaugeState();
}

class _SaThreatGaugeState extends State<SaThreatGauge> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;
  double _previousScore = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _animation = AlwaysStoppedAnimation(widget.score);
    WidgetsBinding.instance.addPostFrameCallback((_) => _animateTo(widget.score));
  }

  @override
  void didUpdateWidget(covariant SaThreatGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.score != widget.score) {
      _previousScore = oldWidget.score;
      _animateTo(widget.score);
    }
  }

  void _animateTo(double target) {
    _animation = Tween<double>(begin: _previousScore, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final value = _animation.value.clamp(0.0, 1.0);
        final level = ThreatLevel.fromScore(value);
        return Semantics(
          label: 'Threat level ${(value * 100).round()}, ${level.label}',
          child: RepaintBoundary(
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: Size.square(widget.size),
                    painter: _GaugePainter(value: value, saColors: saColors),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(value * 100).round()}',
                        style: AppTypography.monoDataL.copyWith(color: onSurface),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'THREAT LEVEL',
                        style: AppTypography.labelM.copyWith(color: onSurface.withValues(alpha: 0.5)),
                      ),
                      Text(
                        level.label,
                        style: AppTypography.headingS.copyWith(color: level.color(context)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value, required this.saColors});

  final double value;
  final SafeHerColors saColors;

  static const _startAngle = 135 * math.pi / 180; // bottom-left
  static const _sweepAngle = 270 * math.pi / 180;

  static const _bands = [
    (0.0, 0.40),
    (0.40, 0.61),
    (0.61, 0.75),
    (0.75, 1.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = saColors.surfaceHighest
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12;
    canvas.drawArc(rect, _startAngle, _sweepAngle, false, trackPaint);

    final colors = [saColors.threatSafe, saColors.threatCaution, saColors.threatElevated, saColors.threatDanger];
    for (var i = 0; i < _bands.length; i++) {
      final (start, end) = _bands[i];
      final bandPaint = Paint()
        ..color = colors[i].withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        rect,
        _startAngle + _sweepAngle * start,
        _sweepAngle * (end - start),
        false,
        bandPaint,
      );
    }

    final needleAngle = _startAngle + _sweepAngle * value;
    final needleLength = radius - 4;
    final needleEnd = Offset(
      center.dx + needleLength * math.cos(needleAngle),
      center.dy + needleLength * math.sin(needleAngle),
    );
    final needlePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, needleEnd, needlePaint);
    canvas.drawCircle(center, 5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) => oldDelegate.value != value;
}
