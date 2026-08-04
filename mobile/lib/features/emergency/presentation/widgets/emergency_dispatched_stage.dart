import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/buttons/sa_button.dart';
import '../../../../shared/components/cards/sa_contact_card.dart';
import '../../../../shared/components/icons/sa_icon.dart';
import '../../domain/models/emergency_contact_summary.dart';

/// Stage 3 — the alert has been sent. Shows a simulated "sharing your
/// location" panel and staggers each contact from "Notifying…" to
/// "Notified" as [notifiedContactIds] grows.
class EmergencyDispatchedStage extends StatelessWidget {
  const EmergencyDispatchedStage({
    required this.contactsAsync,
    required this.notifiedContactIds,
    required this.onMarkSafe,
    super.key,
  });

  final AsyncValue<List<EmergencyContactSummary>> contactsAsync;
  final Set<String> notifiedContactIds;
  final VoidCallback onMarkSafe;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenMarginPhone,
        AppSpacing.space4,
        AppSpacing.screenMarginPhone,
        AppSpacing.space8,
      ),
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.coral500),
            ),
            const SizedBox(width: AppSpacing.space2),
            Flexible(
              child: Text(
                'Help is on the way',
                style: AppTypography.headingL.copyWith(color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(
          'Emergency services and your contacts have been alerted.',
          style: AppTypography.bodyM.copyWith(color: Colors.white.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: AppSpacing.space5),
        const _LiveLocationPanel(),
        const SizedBox(height: AppSpacing.space6),
        Text('Notifying', style: AppTypography.headingS.copyWith(color: Colors.white)),
        const SizedBox(height: AppSpacing.space3),
        contactsAsync.when(
          data: (contacts) => Column(
            children: [
              for (final contact in contacts) ...[
                SaContactCard(
                  name: contact.name,
                  relationship: contact.relationship,
                  priority: contact.priority,
                  confirmed: notifiedContactIds.contains(contact.id),
                ),
                const SizedBox(height: AppSpacing.space3),
              ],
            ],
          ),
          loading: () => const SizedBox(
            height: 48,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (error, stackTrace) => Text(
            "Couldn't load emergency contacts.",
            style: AppTypography.bodyM.copyWith(color: Colors.white.withValues(alpha: 0.6)),
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
        SaButton(
          label: "I'm Safe — Cancel Alert",
          variant: SaButtonVariant.danger,
          confirmRequired: true,
          fullWidth: true,
          onPressed: onMarkSafe,
        ),
      ],
    );
  }
}

class _LiveLocationPanel extends StatelessWidget {
  const _LiveLocationPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: AppColors.dark800,
        borderRadius: AppRadius.xl2Radius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          const SaIcon(SaIconGlyph.mapPin, size: 32, color: AppColors.coral500),
          const SizedBox(width: AppSpacing.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Sharing live location', style: AppTypography.headingS.copyWith(color: Colors.white)),
                const SizedBox(height: AppSpacing.space1),
                Text(
                  'Your location updates automatically as you move.',
                  style: AppTypography.bodyS.copyWith(color: Colors.white.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
