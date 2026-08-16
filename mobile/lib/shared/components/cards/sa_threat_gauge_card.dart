import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../models/threat_level.dart';
import '../charts/sa_threat_gauge.dart';
import '../icons/sa_icon.dart';
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
///
/// [score] is null whenever there's no live threat data to show — no
/// wearable has ever reported in, or the backend has no live score for
/// this user yet. That renders a distinct "waiting for device data" state
/// instead of a gauge sitting at a fake 0%, which would otherwise read as
/// a confirmed-safe reading rather than the absence of any reading at all.
class SaThreatGaugeCard extends StatelessWidget {
  const SaThreatGaugeCard({
    required this.score,
    required this.componentScores,
    required this.lastUpdated,
    super.key,
    this.gaugeSize = 140,
  });

  final double? score;
  final List<SaComponentScore> componentScores;
  final String? lastUpdated;
  final double gaugeSize;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final currentScore = score;

    if (currentScore == null) {
      return SaCard(
        semanticsLabel: 'Threat monitoring, waiting for live device data',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SaIcon(SaIconGlyph.shield, size: 28, color: onSurface.withValues(alpha: 0.4)),
                const SizedBox(width: AppSpacing.space3),
                Expanded(
                  child: Text('Threat Monitoring', style: AppTypography.headingS.copyWith(color: onSurface)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space3),
            Text(
              'Waiting for live device data',
              style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: AppSpacing.space1),
            Text(
              'Connect a Smart Glove or Smart Glasses to begin monitoring.',
              style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.5)),
            ),
          ],
        ),
      );
    }

    final level = ThreatLevel.fromScore(currentScore);

    return SaCard(
      semanticsLabel: 'Threat status card, score ${(currentScore * 100).round()}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // A header, so the gauge no longer has to caption itself. The old
          // layout put "THREAT LEVEL" inside the dial, where it collided
          // with the needle and the score.
          Row(
            children: [
              SaIcon(SaIconGlyph.shield, size: 18, color: level.color(context)),
              const SizedBox(width: AppSpacing.space2),
              Expanded(
                child: Text(
                  'Threat Level',
                  style: AppTypography.labelL.copyWith(
                    color: onSurface.withValues(alpha: 0.75),
                  ),
                ),
              ),
              if (lastUpdated != null)
                Text(
                  lastUpdated!,
                  style: AppTypography.bodyS.copyWith(
                    color: onSurface.withValues(alpha: 0.45),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space4),
          if (componentScores.isEmpty)
            // Nothing to sit beside, so the gauge is centred rather than
            // left-aligned against empty space — which is what made the card
            // look lopsided with an orphaned timestamp underneath.
            Center(child: SaThreatGauge(score: currentScore, size: gaugeSize))
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SaThreatGauge(score: currentScore, size: gaugeSize),
                const SizedBox(width: AppSpacing.space5),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < componentScores.length; i++) ...[
                        _MiniScore(component: componentScores[i]),
                        if (i != componentScores.length - 1)
                          const SizedBox(height: AppSpacing.space3),
                      ],
                    ],
                  ),
                ),
              ],
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
    final value = component.score.clamp(0.0, 1.0);
    // Coloured by its own reading rather than the theme's default indigo:
    // a motion score of 0.9 and an audio score of 0.1 should not look alike
    // on a card whose whole job is conveying severity at a glance.
    final color = ThreatLevel.fromScore(value).color(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                component.label,
                style: AppTypography.labelM.copyWith(color: onSurface.withValues(alpha: 0.7)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${(value * 100).round()}',
              style: AppTypography.monoDataS.copyWith(color: onSurface.withValues(alpha: 0.85)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: AppRadius.fullRadius,
          child: LinearProgressIndicator(
            value: value,
            minHeight: 6,
            color: color,
            backgroundColor: onSurface.withValues(alpha: 0.10),
          ),
        ),
      ],
    );
  }
}
