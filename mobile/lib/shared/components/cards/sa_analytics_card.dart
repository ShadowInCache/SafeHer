import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import 'sa_card.dart';

/// Generic chart wrapper card: title, optional trailing action link, and
/// the chart widget itself.
class SaAnalyticsCard extends StatelessWidget {
  const SaAnalyticsCard({
    required this.title,
    required this.chart,
    super.key,
    this.action,
    this.onActionTap,
    this.useBlur = true,
  });

  final String title;
  final Widget chart;
  final String? action;
  final VoidCallback? onActionTap;
  final bool useBlur;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SaCard(
      useBlur: useBlur,
      semanticsLabel: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.headingS.copyWith(color: onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (action != null) const SizedBox(width: AppSpacing.space2),
              if (action != null)
                GestureDetector(
                  onTap: onActionTap,
                  child: Semantics(
                    label: action,
                    button: onActionTap != null,
                    child: Text(action!, style: AppTypography.labelL.copyWith(color: AppColors.violet500)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space3),
          chart,
        ],
      ),
    );
  }
}
