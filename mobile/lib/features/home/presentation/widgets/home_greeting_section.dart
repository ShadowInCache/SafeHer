import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/buttons/sa_icon_button.dart';
import '../../../../shared/components/icons/sa_icon.dart';
import '../../../monitoring/data/monitoring_providers.dart';

/// Greeting header: avatar, "Good {time}, {name}", search, bell, date, and
/// a status chip reflecting the *real* live-monitoring connection state —
/// not a hardcoded "Monitoring Active" label. [parallaxOffset] is applied
/// as a vertical translate so the section scrolls at 0.5x speed.
class HomeGreetingSection extends StatelessWidget {
  const HomeGreetingSection({
    required this.userName,
    required this.monitoringStatus,
    required this.onBellTap,
    required this.onSearchTap,
    super.key,
    this.parallaxOffset = 0,
  });

  final String userName;
  final MonitoringConnectionStatus monitoringStatus;
  final VoidCallback onBellTap;
  final VoidCallback onSearchTap;
  final double parallaxOffset;

  (String, Color) _statusChip() => switch (monitoringStatus) {
    MonitoringConnectionStatus.connected => ('Monitoring Active', AppColors.success500),
    MonitoringConnectionStatus.connecting => ('Connecting…', AppColors.warning500),
    MonitoringConnectionStatus.disconnected => ('Monitoring Offline', AppColors.neutral400),
  };

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Transform.translate(
      offset: Offset(0, parallaxOffset * 0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone, vertical: AppSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.violet500, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                    style: AppTypography.headingS.copyWith(color: onSurface),
                  ),
                ),
                const SizedBox(width: AppSpacing.space3),
                Expanded(
                  child: Text(
                    '$_greeting, $userName',
                    style: AppTypography.headingL.copyWith(color: onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SaIconButton(
                  icon: const SaIcon(SaIconGlyph.search),
                  semanticsLabel: 'Search',
                  onPressed: onSearchTap,
                ),
                SaIconButton(
                  icon: const SaIcon(SaIconGlyph.bell),
                  semanticsLabel: 'Notifications',
                  onPressed: onBellTap,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space3),
            Row(
              children: [
                Flexible(
                  child: Text(
                    DateFormat('EEEE, MMMM d').format(DateTime.now()),
                    style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.6)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.space3),
                Builder(
                  builder: (context) {
                    final (label, color) = _statusChip();
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: AppRadius.fullRadius,
                      ),
                      child: Text(label, style: AppTypography.labelM.copyWith(color: color)),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
