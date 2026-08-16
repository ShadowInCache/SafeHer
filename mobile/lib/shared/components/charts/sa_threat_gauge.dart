import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/animations/animation_helpers.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../models/threat_level.dart';

/// The app's headline reading: current threat [score] (0.0–1.0) on a
/// coloured arc, with the number and state in the middle.
///
/// **Why there is no needle.** The SRS asks for a centre-pivoted needle, and
/// that is what shipped first — but a needle on a 270° dial sweeps through
/// the middle of the dial, which is also the only place the score can go. At
/// DANGER the needle ran straight through the word "DANGER", and the
/// three-line caption was taller than the free space so it collided with the
/// arc as well. The most important component in the app was the least
/// legible.
///
/// A filled progress arc with a knob at its head carries the same
/// information — position along a scale — while leaving the centre clear.
/// The reading stays glanceable at DANGER, which is the moment it matters.
class SaThreatGauge extends StatefulWidget {
  const SaThreatGauge({required this.score, super.key, this.size = 200});

  final double score;
  final double size;

  @override
  State<SaThreatGauge> createState() => _SaThreatGaugeState();
}

class _SaThreatGaugeState extends State<SaThreatGauge> with TickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;

  /// Ambient breathing at DANGER (SRS §"glowPulse"). Separate controller so
  /// it can repeat without restarting the value animation.
  late final AnimationController _pulseController;

  double _previousScore = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    // The first frame shows the real reading, with no sweep up from zero.
    //
    // The gauge used to animate in from 0 on every mount, which meant that
    // for the first second after opening a screen it displayed a number
    // that was not the threat score — reading SAFE while the actual state
    // was DANGER. On a safety readout that is not a flourish worth having;
    // a value the user can trust the instant it appears is worth more.
    // Changes still animate, which is where the motion actually carries
    // meaning: it shows the score moving, and in which direction.
    _previousScore = widget.score;
    _animation = AlwaysStoppedAnimation(widget.score);

    // The danger glow still needs a frame, because it reads MediaQuery for
    // the reduced-motion check.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPulse(widget.score);
    });
  }

  @override
  void didUpdateWidget(covariant SaThreatGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.score != widget.score) {
      _previousScore = oldWidget.score;
      _animateTo(widget.score);
      _syncPulse(widget.score);
    }
  }

  void _animateTo(double target) {
    _animation = Tween<double>(begin: _previousScore, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    if (AnimationHelpers.reducedMotion(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  void _syncPulse(double score) {
    if (ThreatLevel.fromScore(score) == ThreatLevel.danger) {
      AnimationHelpers.repeat(context, _pulseController, reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return AnimatedBuilder(
      animation: Listenable.merge([_animation, _pulseController]),
      builder: (context, child) {
        final value = _animation.value.clamp(0.0, 1.0);
        final level = ThreatLevel.fromScore(value);
        final displayed = (value * 100).round();

        return Semantics(
          label: 'Threat level $displayed out of 100, ${level.label}',
          child: RepaintBoundary(
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: Size.square(widget.size),
                    painter: _GaugePainter(
                      value: value,
                      levelColor: level.color(context),
                      glowColor: level.glowColor(context),
                      trackColor: saColors.surfaceHighest,
                      pulse: _pulseController.value,
                      zoneColors: [
                        saColors.threatSafe,
                        saColors.threatCaution,
                        saColors.threatElevated,
                        saColors.threatDanger,
                      ],
                    ),
                  ),
                  // Sized to the arc's inner circle so the readout can never
                  // grow into the track, whatever the font scale.
                  SizedBox(
                    width: widget.size * 0.62,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '$displayed',
                            style: AppTypography.monoDataL.copyWith(
                              color: onSurface,
                              height: 1,
                            ),
                          ),
                        ),
                        SizedBox(height: widget.size * 0.04),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            level.label,
                            style: AppTypography.labelM.copyWith(
                              color: level.color(context),
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
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
  _GaugePainter({
    required this.value,
    required this.levelColor,
    required this.glowColor,
    required this.trackColor,
    required this.zoneColors,
    required this.pulse,
  });

  final double value;
  final Color levelColor;
  final Color glowColor;
  final Color trackColor;
  final List<Color> zoneColors;
  final double pulse;

  /// 240° rather than the original 270°: the wider gap at the bottom reads
  /// as a deliberate opening rather than an arc that failed to close, and it
  /// keeps both end caps clear of the card's edges.
  static const _startAngle = 150 * math.pi / 180;
  static const _sweepAngle = 240 * math.pi / 180;

  /// Band lower bounds from [ThreatLevel]. Because the gradient is given
  /// the arc's own start and end angles, these are fractions of the arc and
  /// need no scaling.
  static const _bandStops = [0.0, 0.40, 0.61, 0.75];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final stroke = size.width * 0.085;
    final radius = size.width / 2 - stroke / 2 - size.width * 0.04;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 1. Track.
    canvas.drawArc(
      rect,
      _startAngle,
      _sweepAngle,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );

    if (value <= 0) return;

    final sweep = _sweepAngle * value;

    // 3. Glow under the progress arc; breathes at DANGER.
    canvas.drawArc(
      rect,
      _startAngle,
      sweep,
      false,
      Paint()
        ..color = glowColor.withValues(alpha: 0.55 + 0.25 * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + size.width * (0.05 + 0.02 * pulse)
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.05),
    );

    // 4. Progress arc, ramped through the four threat zones rather than
    // painted a single flat colour.
    //
    // A flat arc would say "you are in DANGER" along its whole length,
    // including the stretch that represents safe readings. The ramp keeps
    // the SRS's four zones legible — greener behind you, redder ahead —
    // while still ending in the colour of the current state.
    canvas.drawArc(
      rect,
      _startAngle,
      sweep,
      false,
      Paint()
        ..shader = SweepGradient(
          // startAngle/endAngle rather than a GradientRotation transform:
          // GradientRotation rotates about the canvas origin, not the centre
          // of the bounds, which slid the ramp off the arc — at low scores
          // the visible stretch landed in a part of the gradient that never
          // showed the zone colour at all.
          startAngle: _startAngle,
          endAngle: _startAngle + _sweepAngle,
          colors: zoneColors,
          stops: _bandStops,
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );

    // 5. Knob at the head of the arc — the needle's job, done without
    // crossing the centre where the score lives.
    final knobAngle = _startAngle + sweep;
    final knob = Offset(
      center.dx + radius * math.cos(knobAngle),
      center.dy + radius * math.sin(knobAngle),
    );
    final knobRadius = stroke * 0.62;
    canvas.drawCircle(
      knob,
      knobRadius + size.width * 0.02,
      Paint()
        ..color = glowColor
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.03),
    );
    canvas.drawCircle(knob, knobRadius, Paint()..color = Colors.white);
    canvas.drawCircle(knob, knobRadius * 0.45, Paint()..color = levelColor);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.levelColor != levelColor ||
      oldDelegate.pulse != pulse ||
      oldDelegate.trackColor != trackColor;
}
