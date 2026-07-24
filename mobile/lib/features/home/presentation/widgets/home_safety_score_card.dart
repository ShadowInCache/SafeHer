import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/cards/sa_card.dart';
import '../../../../shared/components/cards/sa_stat_card.dart';
import '../../../../shared/components/feedback/sa_progress_ring.dart';
import '../../domain/models/home_summary.dart';

class HomeSafetyScoreCard extends StatelessWidget {
  const HomeSafetyScoreCard({required this.summary, super.key});

  final SafetyScoreSummary summary;

  String get _trendGlyph => switch (summary.trend) {
    SaTrendDirection.up => '▲',
    SaTrendDirection.down => '▼',
    SaTrendDirection.flat => '–',
  };

  Color _trendColor() => switch (summary.trend) {
    SaTrendDirection.up => AppColors.success500,
    SaTrendDirection.down => AppColors.danger500,
    SaTrendDirection.flat => AppColors.neutral400,
  };

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SaCard(
      semanticsLabel: 'Daily safety score ${summary.score} out of 100',
      child: Row(
        children: [
          SaProgressRing(progress: summary.score / 100, label: '${summary.score}', size: 64, strokeWidth: 6),
          const SizedBox(width: AppSpacing.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Daily Safety Score', style: AppTypography.headingS.copyWith(color: onSurface)),
                const SizedBox(height: AppSpacing.space1),
                Row(
                  children: [
                    Text(
                      '${summary.streakDays} day streak',
                      style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(width: AppSpacing.space2),
                    Text(_trendGlyph, style: AppTypography.labelM.copyWith(color: _trendColor())),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
