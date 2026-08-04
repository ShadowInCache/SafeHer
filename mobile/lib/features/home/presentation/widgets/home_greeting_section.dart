import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/buttons/sa_icon_button.dart';
import '../../../../shared/components/icons/sa_icon.dart';

/// Greeting header: avatar, "Good {time}, {name}", search, bell (with
/// unread badge), date, and a "Monitoring Active" chip. [parallaxOffset]
/// is applied as a vertical translate so the section scrolls at 0.5x speed.
class HomeGreetingSection extends StatelessWidget {
  const HomeGreetingSection({
    required this.userName,
    required this.hasUnreadAlerts,
    required this.onBellTap,
    required this.onSearchTap,
    super.key,
    this.parallaxOffset = 0,
  });

  final String userName;
  final bool hasUnreadAlerts;
  final VoidCallback onBellTap;
  final VoidCallback onSearchTap;
  final double parallaxOffset;

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
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    SaIconButton(
                      icon: const SaIcon(SaIconGlyph.bell),
                      semanticsLabel: hasUnreadAlerts ? 'Notifications, unread alerts' : 'Notifications',
                      onPressed: onBellTap,
                    ),
                    if (hasUnreadAlerts)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.coral500),
                        ),
                      ),
                  ],
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success500.withValues(alpha: 0.15),
                    borderRadius: AppRadius.fullRadius,
                  ),
                  child: Text(
                    'Monitoring Active',
                    style: AppTypography.labelM.copyWith(color: AppColors.success500),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
