import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../models/threat_level.dart';
import '../feedback/sa_threat_chip.dart';
import 'sa_card.dart';

/// Recent-alert summary row: title, timestamp, threat chip, snippet.
class SaAlertCard extends StatelessWidget {
  const SaAlertCard({
    required this.title,
    required this.timestamp,
    required this.level,
    required this.summary,
    super.key,
    this.onTap,
    this.useBlur = true,
  });

  final String title;
  final String timestamp;
  final ThreatLevel level;
  final String summary;
  final VoidCallback? onTap;
  final bool useBlur;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SaCard(
      onTap: onTap,
      useBlur: useBlur,
      semanticsLabel: '$title, ${level.label}, $timestamp',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppTypography.headingS.copyWith(color: onSurface))),
              SaThreatChip(level: level, compact: true),
            ],
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(timestamp, style: AppTypography.monoDataS.copyWith(color: onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: AppSpacing.space2),
          Text(
            summary,
            style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.8)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
