import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../charts/sa_threat_gauge.dart';
import 'sa_card.dart';

class SaComponentScore {
  const SaComponentScore({required this.label, required this.score});

  final String label;

  /// 0.0–1.0
  final double score;
}

/// Home/Live-Monitor threat status card: the animated gauge on the left,
/// per-component (Motion/Audio/Vision) mini score bars on the right, and a
/// last-updated timestamp beneath.
class SaThreatGaugeCard extends StatelessWidget {
  const SaThreatGaugeCard({
    required this.score,
    required this.componentScores,
    required this.lastUpdated,
    super.key,
    this.gaugeSize = 140,
  });

  final double score;
  final List<SaComponentScore> componentScores;
  final String lastUpdated;
  final double gaugeSize;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SaCard(
      semanticsLabel: 'Threat status card, score ${(score * 100).round()}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SaThreatGauge(score: score, size: gaugeSize),
              const SizedBox(width: AppSpacing.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final component in componentScores) ...[
                      _MiniScore(component: component),
                      const SizedBox(height: AppSpacing.space3),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            'Last updated $lastUpdated',
            style: AppTypography.monoDataS.copyWith(color: onSurface.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }
}

class _MiniScore extends StatelessWidget {
  const _MiniScore({required this.component});

  final SaComponentScore component;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(component.label, style: AppTypography.labelM.copyWith(color: onSurface.withValues(alpha: 0.7))),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: AppRadius.fullRadius,
          child: LinearProgressIndicator(
            value: component.score.clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: onSurface.withValues(alpha: 0.1),
          ),
        ),
      ],
    );
  }
}
