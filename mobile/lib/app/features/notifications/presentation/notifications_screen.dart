import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/premium_theme.dart';
import '../../../shared/models/domain_models.dart';
import '../../../shared/state/providers.dart';
import '../../../shared/widgets/glass_card.dart';

class NotificationsCenterScreen extends ConsumerWidget {
  const NotificationsCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safety = ref.watch(safetyControllerProvider);
    final notifier = ref.read(safetyControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _countChip(
                  'Total',
                  safety.notifications.length,
                  Colors.blueGrey,
                ),
                _countChip(
                  'Danger',
                  safety.notifications
                      .where((n) => n.severity == ThreatLevelState.danger)
                      .length,
                  PremiumTheme.danger,
                ),
                _countChip(
                  'Warning',
                  safety.notifications
                      .where((n) => n.severity == ThreatLevelState.warning)
                      .length,
                  PremiumTheme.warning,
                ),
                _countChip(
                  'Unread',
                  safety.notifications.where((n) => !n.read).length,
                  PremiumTheme.accent,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (safety.notifications.isEmpty)
            const GlassCard(child: Text('No notifications yet.'))
          else
            ...safety.notifications.map(
              (notification) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  tint: notification.read
                      ? Colors.transparent
                      : _severityColor(
                          notification.severity,
                        ).withValues(alpha: 0.2),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _severityIcon(notification.severity),
                      color: _severityColor(notification.severity),
                    ),
                    title: Text(notification.title),
                    subtitle: Text(
                      '${notification.body}\n${notification.time.toLocal()}',
                    ),
                    isThreeLine: true,
                    trailing: notification.read
                        ? const Icon(Icons.done_all)
                        : TextButton(
                            onPressed: () =>
                                notifier.markNotificationRead(notification.id),
                            child: const Text('Mark read'),
                          ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _countChip(String label, int count, Color color) {
    return Chip(
      label: Text('$label: $count'),
      backgroundColor: color.withValues(alpha: 0.2),
      side: BorderSide(color: color.withValues(alpha: 0.5)),
    );
  }

  Color _severityColor(ThreatLevelState severity) {
    return switch (severity) {
      ThreatLevelState.safe => PremiumTheme.safe,
      ThreatLevelState.warning => PremiumTheme.warning,
      ThreatLevelState.danger => PremiumTheme.danger,
    };
  }

  IconData _severityIcon(ThreatLevelState severity) {
    return switch (severity) {
      ThreatLevelState.safe => Icons.notifications_active_outlined,
      ThreatLevelState.warning => Icons.warning_amber_rounded,
      ThreatLevelState.danger => Icons.notification_important_rounded,
    };
  }
}
