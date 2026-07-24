import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/theme/premium_theme.dart';
import '../../../shared/models/domain_models.dart';
import '../../../shared/state/providers.dart';
import '../../../shared/widgets/glass_card.dart';

class IncidentHistoryScreenV2 extends ConsumerStatefulWidget {
  const IncidentHistoryScreenV2({super.key});

  @override
  ConsumerState<IncidentHistoryScreenV2> createState() =>
      _IncidentHistoryScreenV2State();
}

class _IncidentHistoryScreenV2State
    extends ConsumerState<IncidentHistoryScreenV2> {
  String _query = '';
  ThreatLevelState? _filter;

  @override
  Widget build(BuildContext context) {
    final safety = ref.watch(safetyControllerProvider);
    final incidents = safety.incidents.where((incident) {
      final filterMatch = _filter == null || incident.severity == _filter;
      final queryMatch =
          _query.trim().isEmpty ||
          incident.summary.toLowerCase().contains(_query.toLowerCase());
      return filterMatch && queryMatch;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Incident History',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search incidents',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                  ...ThreatLevelState.values.map(
                    (level) => ChoiceChip(
                      label: Text(level.name),
                      selected: _filter == level,
                      onSelected: (_) => setState(() => _filter = level),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (incidents.isEmpty)
          const GlassCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('No incidents found for selected filters.'),
            ),
          )
        else
          ...incidents.map(
            (incident) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    AppRoutes.incidentDetails,
                    arguments: incident,
                  );
                },
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: _severityColor(
                      incident.severity,
                    ).withValues(alpha: 0.2),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: _severityColor(incident.severity),
                    ),
                  ),
                  title: Text(incident.summary),
                  subtitle: Text(
                    '${incident.createdAt.toLocal()} • ${incident.location.latitude.toStringAsFixed(4)}, ${incident.location.longitude.toStringAsFixed(4)}',
                  ),
                  trailing: Text(
                    incident.severity.name.toUpperCase(),
                    style: TextStyle(
                      color: _severityColor(incident.severity),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Color _severityColor(ThreatLevelState severity) {
    return switch (severity) {
      ThreatLevelState.safe => PremiumTheme.safe,
      ThreatLevelState.warning => PremiumTheme.warning,
      ThreatLevelState.danger => PremiumTheme.danger,
    };
  }
}
