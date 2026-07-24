import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/theme/premium_theme.dart';
import '../../../shared/models/domain_models.dart';
import '../../../shared/state/providers.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/risk_gauge.dart';

class HomeDashboardScreen extends ConsumerWidget {
  const HomeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final safety = ref.watch(safetyControllerProvider);

    return RefreshIndicator(
      onRefresh: () async {
        final userId = session.user?.id;
        if (userId != null) {
          await ref
              .read(safetyControllerProvider.notifier)
              .initialize(userId: userId);
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: [
          GlassCard(
            tint: _statusColor(safety.threatLevel),
            child: Row(
              children: [
                RiskGauge(score: safety.threatScore, size: 130),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Safety Status',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _statusTitle(safety.threatLevel),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(color: _statusColor(safety.threatLevel)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Live AI score combines motion, voice, weapon, and contextual risk analysis.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _DeviceCard(device: safety.glove)),
              const SizedBox(width: 10),
              Expanded(child: _DeviceCard(device: safety.glasses)),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: PremiumTheme.danger,
              minimumSize: const Size.fromHeight(60),
            ),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.sos),
            icon: const Icon(Icons.sos, color: Colors.white),
            label: const Text(
              'Quick SOS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Live GPS',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(
                        context,
                        AppRoutes.liveTrackingMap,
                      ),
                      child: const Text('Open Map'),
                    ),
                  ],
                ),
                Text(
                  'Lat ${safety.currentLocation.latitude.toStringAsFixed(5)}, Lng ${safety.currentLocation.longitude.toStringAsFixed(5)}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Nearby safe place ETA: 6 mins',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recent Incidents',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (safety.incidents.isEmpty)
                  const Text('No incidents recorded today.')
                else
                  ...safety.incidents
                      .take(3)
                      .map(
                        (incident) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.report_problem_outlined,
                            color: _statusColor(incident.severity),
                          ),
                          title: Text(incident.summary),
                          subtitle: Text(
                            incident.createdAt.toLocal().toString(),
                          ),
                          trailing: TextButton(
                            onPressed: () => Navigator.pushNamed(
                              context,
                              AppRoutes.incidentDetails,
                              arguments: incident,
                            ),
                            child: const Text('Details'),
                          ),
                        ),
                      ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nearby Safe Zones',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    Chip(label: Text('Police Station - 1.2 km')),
                    Chip(label: Text('City Hospital - 2.4 km')),
                    Chip(label: Text('Women Shelter - 3.1 km')),
                    Chip(label: Text('Metro Hub - 0.7 km')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Personalized Safety Tips',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ...safety.personalizedTips.map(
                  (tip) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tip),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Row(
              children: [
                const Icon(Icons.today_outlined, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Daily Summary: ${safety.timeline.length} events analyzed, '
                    '${safety.incidents.length} incidents recorded, '
                    'wearables ${safety.glove.connected && safety.glasses.connected ? 'fully connected' : 'partially connected'}.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(ThreatLevelState level) {
    return switch (level) {
      ThreatLevelState.safe => PremiumTheme.safe,
      ThreatLevelState.warning => PremiumTheme.warning,
      ThreatLevelState.danger => PremiumTheme.danger,
    };
  }

  String _statusTitle(ThreatLevelState level) {
    return switch (level) {
      ThreatLevelState.safe => 'SAFE',
      ThreatLevelState.warning => 'WARNING',
      ThreatLevelState.danger => 'DANGER',
    };
  }
}

class _DeviceCard extends StatelessWidget {
  final WearableDeviceState device;

  const _DeviceCard({required this.device});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                device.kind == DeviceKind.glove
                    ? Icons.back_hand_outlined
                    : Icons.visibility_outlined,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  device.displayName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Status: ${device.connected ? 'Connected' : 'Disconnected'}'),
          Text('Battery: ${device.battery}%'),
          Text('Signal: ${device.signalStrength}%'),
          Text('Diagnostics: ${device.diagnostics}'),
        ],
      ),
    );
  }
}
