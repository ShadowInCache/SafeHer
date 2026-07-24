import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/premium_theme.dart';
import '../../../shared/models/domain_models.dart';
import '../../../shared/state/providers.dart';
import '../../../shared/widgets/glass_card.dart';

class ThreatMonitoringScreenV2 extends ConsumerWidget {
  const ThreatMonitoringScreenV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safety = ref.watch(safetyControllerProvider);
    final normalized = (safety.threatScore / 100).clamp(0.0, 1.0);

    final channels = [
      ('Motion anomaly', (normalized + 0.12).clamp(0.0, 1.0)),
      ('Voice aggression', (normalized + 0.04).clamp(0.0, 1.0)),
      ('Weapon detection', (normalized + 0.08).clamp(0.0, 1.0)),
      ('Suspicious person', (normalized - 0.06).clamp(0.0, 1.0)),
      ('Fall detection', (normalized - 0.10).clamp(0.0, 1.0)),
      ('Forced movement', (normalized + 0.02).clamp(0.0, 1.0)),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassCard(
          tint: _levelColor(safety.threatLevel),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Real-Time Threat Engine',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Current level: ${safety.threatLevel.name.toUpperCase()} (${safety.threatScore.toStringAsFixed(1)}%)',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: _levelColor(safety.threatLevel),
                ),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: normalized,
                minHeight: 10,
                borderRadius: BorderRadius.circular(20),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...channels.map((item) {
          final title = item.$1;
          final confidence = item.$2;
          final color = confidence > 0.7
              ? PremiumTheme.danger
              : confidence > 0.4
              ? PremiumTheme.warning
              : PremiumTheme.safe;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        '${(confidence * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: confidence,
                    color: color,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Event Timeline',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (safety.timeline.isEmpty)
                const Text('No telemetry events yet. Monitoring is active.')
              else
                ...safety.timeline
                    .take(25)
                    .map(
                      (event) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.circle,
                          size: 12,
                          color: _levelColor(event.severity),
                        ),
                        title: Text(event.description),
                        subtitle: Text(
                          '${event.source} • ${(event.confidence * 100).toStringAsFixed(0)}% confidence',
                        ),
                        trailing: Text(
                          '${event.time.hour.toString().padLeft(2, '0')}:${event.time.minute.toString().padLeft(2, '0')}',
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }

  Color _levelColor(ThreatLevelState level) {
    return switch (level) {
      ThreatLevelState.safe => PremiumTheme.safe,
      ThreatLevelState.warning => PremiumTheme.warning,
      ThreatLevelState.danger => PremiumTheme.danger,
    };
  }
}
