import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/icons/sa_icon.dart';

/// Dashed-border "+" card that opens the BLE pairing flow.
class PairDeviceCard extends StatelessWidget {
  const PairDeviceCard({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: 'Pair Device',
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.xl2Radius,
        child: CustomPaint(
          painter: _DashedBorderPainter(color: onSurface.withValues(alpha: 0.3)),
          child: Container(
            height: 120,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SaIcon(SaIconGlyph.plus, size: 28, color: AppColors.violet500),
                const SizedBox(height: AppSpacing.space2),
                Text('Pair Device', style: AppTypography.labelL.copyWith(color: AppColors.violet500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(24));
    final path = Path()..addRRect(rrect);
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dashWidth), paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => oldDelegate.color != color;
}
