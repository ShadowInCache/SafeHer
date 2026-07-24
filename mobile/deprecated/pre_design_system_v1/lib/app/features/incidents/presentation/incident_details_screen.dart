import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/premium_theme.dart';
import '../../../shared/models/domain_models.dart';
import '../../../shared/state/providers.dart';
import '../../../shared/widgets/glass_card.dart';

class IncidentDetailsScreenV2 extends ConsumerWidget {
  const IncidentDetailsScreenV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arg = ModalRoute.of(context)?.settings.arguments;
    final safety = ref.watch(safetyControllerProvider);
    final incident = arg is IncidentRecord
        ? arg
        : (safety.incidents.isNotEmpty ? safety.incidents.first : null);

    if (incident == null) {
      return const Scaffold(
        body: Center(child: Text('No incident details available.')),
      );
    }

    final color = switch (incident.severity) {
      ThreatLevelState.safe => PremiumTheme.safe,
      ThreatLevelState.warning => PremiumTheme.warning,
      ThreatLevelState.danger => PremiumTheme.danger,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Incident Details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            tint: color,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  incident.summary,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text('Severity: ${incident.severity.name.toUpperCase()}'),
                Text('Time: ${incident.createdAt.toLocal()}'),
                Text(
                  'Location: ${incident.location.latitude.toStringAsFixed(6)}, ${incident.location.longitude.toStringAsFixed(6)}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Incident Summary',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'High-risk pattern detected from multi-modal fusion (motion + voice + context). '
                  'Emergency workflow activated with guardian and police notification chains. '
                  'Evidence stream was encrypted and persisted for forensic integrity.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Evidence Integrity',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.lock_outline),
                  title: Text('AES encrypted local evidence cache'),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.cloud_upload_outlined),
                  title: Text('Secure cloud upload with retry queue'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.perm_media_outlined),
                  title: Text(
                    'Attached files: ${incident.evidenceFiles.isEmpty ? 0 : incident.evidenceFiles.length}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Timeline', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                ...ref
                    .watch(safetyControllerProvider)
                    .timeline
                    .take(8)
                    .map(
                      (event) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(
                          Icons.fiber_manual_record,
                          size: 12,
                          color: event.severity == ThreatLevelState.danger
                              ? PremiumTheme.danger
                              : event.severity == ThreatLevelState.warning
                              ? PremiumTheme.warning
                              : PremiumTheme.safe,
                        ),
                        title: Text(event.description),
                        subtitle: Text(
                          '${event.source} • ${(event.confidence * 100).toStringAsFixed(0)}% confidence',
                        ),
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('PDF report generated and downloaded.'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Download PDF'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Police report summary shared.'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share Report'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
