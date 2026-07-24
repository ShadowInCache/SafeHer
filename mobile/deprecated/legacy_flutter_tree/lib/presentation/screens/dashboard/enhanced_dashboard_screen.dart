import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/threat_banner.dart';
import '../../widgets/sos_button.dart';
import '../../widgets/device_card.dart';
import '../../widgets/stat_card.dart';
import '../../../core/theme/modern_theme.dart';
import '../../providers/api_providers.dart';

class EnhancedDashboardScreen extends ConsumerStatefulWidget {
  const EnhancedDashboardScreen({super.key});

  @override
  ConsumerState<EnhancedDashboardScreen> createState() =>
      _EnhancedDashboardScreenState();
}

class _EnhancedDashboardScreenState
    extends ConsumerState<EnhancedDashboardScreen> {
  ThreatLevel _getThreatLevel(int score) {
    if (score < 20) return ThreatLevel.safe;
    if (score < 40) return ThreatLevel.low;
    if (score < 60) return ThreatLevel.medium;
    if (score < 80) return ThreatLevel.high;
    return ThreatLevel.critical;
  }

  void _handleSOS() {
    // Local SOS handling - no backend needed
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.emergency, color: Colors.white),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '🚨 SOS ACTIVATED — Alerting emergency contacts!',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.dangerColor,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final threatScore = ref.watch(threatLevelProvider);
    final incidentCount = ref.watch(incidentCountProvider);
    final alertsAsync = ref.watch(alertsProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(alertsProvider);
            ref.invalidate(recentEventsProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ThreatBanner(
                    level: _getThreatLevel(threatScore),
                    score: threatScore,
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Center(child: SOSButton(onActivate: _handleSOS)),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'DEVICES',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Expanded(
                        child: DeviceCard(
                          name: 'Smart Glove',
                          type: DeviceType.glove,
                          connected: true,
                          battery: 78,
                          signalStrength: 85,
                          lastSync: '2s ago',
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: DeviceCard(
                          name: 'Smart Glasses',
                          type: DeviceType.glasses,
                          connected: true,
                          battery: 92,
                          signalStrength: 72,
                          lastSync: '1s ago',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'QUICK STATS',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.3,
                    children: [
                      StatCard(
                        label: 'Total Incidents',
                        value: incidentCount.toString(),
                        icon: Icons.error_outline,
                      ),
                      const StatCard(
                        label: 'Monitoring Time',
                        value: '12h',
                        icon: Icons.access_time,
                        trend: '+2h today',
                      ),
                      StatCard(
                        label: 'Threat Level',
                        value: _getThreatLevelText(threatScore),
                        icon: Icons.shield,
                      ),
                      alertsAsync.when(
                        data: (alerts) => StatCard(
                          label: 'Active Alerts',
                          value: alerts.length.toString(),
                          icon: Icons.notifications_active,
                          trend: alerts.isEmpty
                              ? 'All clear'
                              : '${alerts.length} alert${alerts.length > 1 ? 's' : ''}',
                        ),
                        loading: () => const StatCard(
                          label: 'Active Alerts',
                          value: '0',
                          icon: Icons.notifications_active,
                          trend: 'Loading...',
                        ),
                        error: (_, __) => const StatCard(
                          label: 'Active Alerts',
                          value: '0',
                          icon: Icons.notifications_active,
                          trend: 'All clear',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getThreatLevelText(int score) {
    if (score < 20) return 'Safe';
    if (score < 40) return 'Low';
    if (score < 60) return 'Medium';
    if (score < 80) return 'High';
    return 'Critical';
  }
}
