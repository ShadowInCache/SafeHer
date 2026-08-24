import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_extensions.dart';
import 'sa_card.dart';

/// Emergency contact row: avatar, name, relationship chip, drag handle for
/// priority reordering (used with a ReorderableListView by the caller).
class SaContactCard extends StatelessWidget {
  const SaContactCard({
    required this.name,
    required this.relationship,
    required this.priority,
    super.key,
    this.confirmed = true,
    this.dragHandle,
    this.onTap,
  });

  final String name;
  final String relationship;
  final int priority;
  final bool confirmed;
  final Widget? dragHandle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SaCard(
      onTap: onTap,
      semanticsLabel: 'Priority $priority, $name, $relationship, ${confirmed ? "confirmed" : "pending"}',
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.violet900, shape: BoxShape.circle),
            child: Text('$priority', style: AppTypography.labelM.copyWith(color: Colors.white)),
          ),
          const SizedBox(width: AppSpacing.space3),
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.violet500,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: AppTypography.headingS.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: AppTypography.headingS.copyWith(color: onSurface)),
                const SizedBox(height: 2),
                // violet500 is the both-grounds compromise, tuned to 3:1 --
                // enough for an icon, not for a 12px label. The resolved
                // interactive colour clears AA on whichever ground it lands
                // on, and the chip fill follows it instead of being a fixed
                // light violet that all but disappeared on the day theme.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.saColors.interactive.withValues(alpha: 0.12),
                    borderRadius: AppRadius.fullRadius,
                  ),
                  child: Text(
                    relationship,
                    style: AppTypography.labelM.copyWith(color: context.saColors.interactive),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: AppSpacing.space2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: confirmed ? AppColors.success500 : AppColors.warning500,
            ),
          ),
          if (dragHandle != null) dragHandle!,
        ],
      ),
    );
  }
}
