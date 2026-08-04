import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/cards/sa_card.dart';
import '../../../../shared/components/charts/sa_threat_gauge.dart';
import '../../../../shared/models/threat_level.dart';

/// Larger standalone gauge for the Live Monitoring screen, Hero-tagged to
/// match Home's threat status card for a morph transition between them.
class ThreatGaugePanel extends StatelessWidget {
  const ThreatGaugePanel({required this.score, super.key});

  final double score;

  @override
  Widget build(BuildContext context) {
    final level = ThreatLevel.fromScore(score);
    return Hero(
      tag: 'threat_gauge',
      child: SaCard(
        semanticsLabel: 'Live threat level, score ${(score * 100).round()}',
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SaThreatGauge(score: score, size: 180),
              const SizedBox(height: AppSpacing.space2),
              Text(
                'THREAT LEVEL — ${level.label}',
                style: AppTypography.headingS.copyWith(color: level.color(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
