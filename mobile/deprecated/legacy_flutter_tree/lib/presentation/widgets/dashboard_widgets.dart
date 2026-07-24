import 'package:flutter/material.dart';
import 'package:safeher_app/core/theme/app_theme.dart';

class DeviceStatusCard extends StatelessWidget {
  final String deviceName;
  final IconData icon;
  final bool isConnected;
  final int batteryLevel;
  final DateTime lastSync;
  final VoidCallback onTap;

  const DeviceStatusCard({
    super.key,
    required this.deviceName,
    required this.icon,
    required this.isConnected,
    required this.batteryLevel,
    required this.lastSync,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isConnected
                          ? AppTheme.successColor.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      icon,
                      color: isConnected ? AppTheme.successColor : Colors.grey,
                      size: 24,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isConnected ? AppTheme.successColor : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                deviceName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.battery_std,
                    size: 16,
                    color: batteryLevel > 20
                        ? AppTheme.successColor
                        : AppTheme.dangerColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$batteryLevel%',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ThreatMeter extends StatelessWidget {
  final double threatScore;
  final VoidCallback onTap;

  const ThreatMeter({
    super.key,
    required this.threatScore,
    required this.onTap,
  });

  Color _getThreatColor() {
    if (threatScore < 0.3) return AppTheme.successColor;
    if (threatScore < 0.5) return Colors.yellow;
    if (threatScore < 0.75) return AppTheme.warningColor;
    return AppTheme.dangerColor;
  }

  String _getThreatLabel() {
    if (threatScore < 0.3) return 'Safe';
    if (threatScore < 0.5) return 'Low Risk';
    if (threatScore < 0.75) return 'Medium Risk';
    if (threatScore < 0.9) return 'High Risk';
    return 'Critical';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Text(
                'Current Threat Level',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: threatScore,
                      strokeWidth: 12,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation(_getThreatColor()),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${(threatScore * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: _getThreatColor(),
                          ),
                        ),
                        Text(
                          _getThreatLabel(),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'All systems operational',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QuickActions extends StatelessWidget {
  final VoidCallback onSOS;
  final VoidCallback onViewIncidents;
  final VoidCallback onManageContacts;
  final VoidCallback onTestAlarm;

  const QuickActions({
    super.key,
    required this.onSOS,
    required this.onViewIncidents,
    required this.onManageContacts,
    required this.onTestAlarm,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: [
        _QuickActionCard(
          icon: Icons.warning_amber_rounded,
          label: 'SOS',
          color: AppTheme.dangerColor,
          onTap: onSOS,
        ),
        _QuickActionCard(
          icon: Icons.history,
          label: 'Incidents',
          color: AppTheme.infoColor,
          onTap: onViewIncidents,
        ),
        _QuickActionCard(
          icon: Icons.contacts,
          label: 'Contacts',
          color: AppTheme.primaryColor,
          onTap: onManageContacts,
        ),
        _QuickActionCard(
          icon: Icons.volume_up,
          label: 'Test Alarm',
          color: AppTheme.warningColor,
          onTap: onTestAlarm,
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 32,
                color: color,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
