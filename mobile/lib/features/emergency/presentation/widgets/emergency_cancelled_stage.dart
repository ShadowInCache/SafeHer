import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/buttons/sa_button.dart';
import '../../../../shared/components/icons/sa_icon.dart';

/// Stage 4 — false-alarm cancellation confirmation.
class EmergencyCancelledStage extends StatelessWidget {
  const EmergencyCancelledStage({required this.onReturnHome, super.key});

  final VoidCallback onReturnHome;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: AppColors.success500.withValues(alpha: 0.15), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const SaIcon(SaIconGlyph.check, size: 32, color: AppColors.success500),
            ),
            const SizedBox(height: AppSpacing.space5),
            Text(
              "You're marked as safe",
              style: AppTypography.headingL.copyWith(color: onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              'Your emergency contacts have been notified that this was a false alarm.',
              style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.6)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.space8),
            SaButton(label: 'Return Home', fullWidth: true, onPressed: onReturnHome),
          ],
        ),
      ),
    );
  }
}
