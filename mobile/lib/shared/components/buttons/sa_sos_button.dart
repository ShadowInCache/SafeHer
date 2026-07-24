import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/animations/animation_helpers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../icons/sa_icon.dart';

/// The 160dp hold-to-confirm SOS button used on the Emergency screen.
/// Holding for [holdDuration] fills the ring and fires [onConfirmed];
/// releasing early resets the ring. Idle state breathes gently to draw
/// the eye without being alarming.
class SaSOSButton extends StatefulWidget {
  const SaSOSButton({
    required this.onConfirmed,
    super.key,
    this.size = 160,
    this.holdDuration = const Duration(milliseconds: 1200),
    this.label = 'SOS',
  });

  final VoidCallback onConfirmed;
  final double size;
  final Duration holdDuration;
  final String label;

  @override
  State<SaSOSButton> createState() => _SaSOSButtonState();
}

class _SaSOSButtonState extends State<SaSOSButton> with TickerProviderStateMixin {
  late final AnimationController _holdController;
  late final AnimationController _breatheController;
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(vsync: this, duration: widget.holdDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_confirmed) {
          _confirmed = true;
          HapticFeedback.heavyImpact();
          widget.onConfirmed();
        }
      });
    _breatheController = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AnimationHelpers.repeat(context, _breatheController, reverse: true);
    });
  }

  @override
  void dispose() {
    _holdController.dispose();
    _breatheController.dispose();
    super.dispose();
  }

  void _onHoldStart() {
    if (_confirmed) return;
    HapticFeedback.mediumImpact();
    AnimationHelpers.forward(context, _holdController);
  }

  void _onHoldEnd() {
    if (_confirmed) return;
    AnimationHelpers.reverse(context, _holdController);
  }

  @override
  Widget build(BuildContext context) {
    final breathe = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut),
    );

    return Semantics(
      label: 'Hold to send emergency SOS alert',
      button: true,
      child: GestureDetector(
        onLongPressStart: (_) => _onHoldStart(),
        onLongPressEnd: (_) => _onHoldEnd(),
        onLongPressCancel: _onHoldEnd,
        child: AnimatedBuilder(
          animation: Listenable.merge([_holdController, breathe]),
          builder: (context, child) {
            return Transform.scale(
              scale: breathe.value,
              child: CustomPaint(
                painter: _HoldRingPainter(progress: _holdController.value),
                child: SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: child,
                ),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: AppColors.coral500, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SaIcon(SaIconGlyph.shield, size: 32, color: Colors.white),
                const SizedBox(height: 4),
                Text(widget.label, style: AppTypography.displayL.copyWith(color: Colors.white, fontSize: 24)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoldRingPainter extends CustomPainter {
  _HoldRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    final track = Paint()
      ..color = AppColors.coral500.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;
    final fill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159 / 2,
      2 * 3.14159 * progress,
      false,
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _HoldRingPainter oldDelegate) => oldDelegate.progress != progress;
}
