import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/cards/sa_card.dart';
import '../../../../shared/components/charts/sa_threat_gauge.dart';
import '../../../../shared/models/threat_level.dart';

/// Larger standalone gauge for the Live Monitoring screen.
///
/// Deliberately not Hero-tagged to match Home's threat status card: this
/// panel only exists once the monitoring stream has emitted its first
/// snapshot, so on slow connections the destination Hero can still be
/// absent when Home's exit transition starts. If the stream's first value
/// then arrives mid-flight, the outgoing and incoming widgets can both be
/// mounted with the same tag in the same frame, which throws ("multiple
/// heroes that share the same tag") and blanks the route.
class ThreatGaugePanel extends StatelessWidget {
  const ThreatGaugePanel({required this.score, super.key});

  final double score;

  @override
  Widget build(BuildContext context) {
    final level = ThreatLevel.fromScore(score);
    return SaCard(
      semanticsLabel: 'Live threat level, score ${(score * 100).round()}',
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Scales with whatever height this panel actually gets instead
            // of a fixed 180 — on short viewports (small phones, or once a
            // floating bottom nav bar eats into this screen's clearance)
            // a fixed size overflowed the card.
            final gaugeSize = constraints.maxHeight.isFinite
                ? (constraints.maxHeight - 56).clamp(80.0, 180.0)
                : 180.0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SaThreatGauge(score: score, size: gaugeSize),
                const SizedBox(height: AppSpacing.space2),
                Text(
                  'THREAT LEVEL — ${level.label}',
                  style: AppTypography.headingS.copyWith(color: level.color(context)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
