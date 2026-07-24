import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/theme_extensions.dart';

/// Animated horizontal battery indicator. Color follows the standard
/// thresholds: green above 20%, amber above 10%, red at or below 10%.
class SaBatteryBar extends StatelessWidget {
  const SaBatteryBar({required this.percent, super.key, this.height = 6});

  /// 0.0–1.0
  final double percent;
  final double height;

  Color _colorFor(double p) {
    if (p > 0.2) return AppColors.success500;
    if (p > 0.1) return AppColors.warning500;
    return AppColors.danger500;
  }

  @override
  Widget build(BuildContext context) {
    final clamped = percent.clamp(0.0, 1.0);
    final saColors = context.saColors;
    return Semantics(
      label: 'Battery ${(clamped * 100).round()} percent',
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Container(
                height: height,
                width: constraints.maxWidth,
                decoration: BoxDecoration(color: saColors.surfaceHighest, borderRadius: AppRadius.fullRadius),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOutCubic,
                height: height,
                width: constraints.maxWidth * clamped,
                decoration: BoxDecoration(color: _colorFor(clamped), borderRadius: AppRadius.fullRadius),
              ),
            ],
          );
        },
      ),
    );
  }
}
