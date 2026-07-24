import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';

/// 3-bar signal strength indicator, filling from the bottom bar upward.
class SaSignalBars extends StatelessWidget {
  const SaSignalBars({required this.strength, super.key, this.barWidth = 4, this.maxHeight = 16});

  /// 0, 1, 2, or 3 bars filled.
  final int strength;
  final double barWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    final heights = [0.4, 0.7, 1.0];
    return Semantics(
      label: 'Signal strength $strength of 3',
      child: SizedBox(
        height: maxHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(3, (i) {
            final filled = i < strength;
            return Padding(
              padding: EdgeInsets.only(right: i < 2 ? 3 : 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                width: barWidth,
                height: maxHeight * heights[i],
                decoration: BoxDecoration(
                  color: filled ? AppColors.violet500 : saColors.surfaceHighest,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
