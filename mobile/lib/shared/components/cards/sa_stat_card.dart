import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../icons/sa_icon.dart';
import 'sa_card.dart';

enum SaTrendDirection { up, down, flat }

/// Compact stat tile: large number, label, trend arrow, icon.
class SaStatCard extends StatelessWidget {
  const SaStatCard({
    required this.value,
    required this.label,
    super.key,
    this.trend,
    this.icon,
    this.useBlur = true,
  });

  final String value;
  final String label;
  final SaTrendDirection? trend;
  final SaIconGlyph? icon;
  final bool useBlur;

  Color _trendColor(SaTrendDirection direction) => switch (direction) {
    SaTrendDirection.up => AppColors.success500,
    SaTrendDirection.down => AppColors.danger500,
    SaTrendDirection.flat => AppColors.neutral400,
  };

  String _trendGlyph(SaTrendDirection direction) => switch (direction) {
    SaTrendDirection.up => '▲',
    SaTrendDirection.down => '▼',
    SaTrendDirection.flat => '–',
  };

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SaCard(
      useBlur: useBlur,
      semanticsLabel: '$label: $value',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (icon != null) SaIcon(icon!, size: 20, color: AppColors.violet500),
              if (trend != null)
                Text(
                  _trendGlyph(trend!),
                  style: AppTypography.labelM.copyWith(color: _trendColor(trend!)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(value, style: AppTypography.monoDataL.copyWith(color: onSurface)),
          const SizedBox(height: AppSpacing.space1),
          Text(label, style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}
