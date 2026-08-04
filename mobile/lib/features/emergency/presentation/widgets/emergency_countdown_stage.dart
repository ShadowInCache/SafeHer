import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/buttons/sa_button.dart';
import '../../../../shared/components/feedback/sa_progress_ring.dart';

/// Stage 2 — a cancellable countdown before the alert actually dispatches.
class EmergencyCountdownStage extends StatelessWidget {
  const EmergencyCountdownStage({
    required this.secondsRemaining,
    required this.totalSeconds,
    required this.onCancel,
    super.key,
  });

  final int secondsRemaining;
  final int totalSeconds;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final progress = 1 - (secondsRemaining / totalSeconds);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sending alert in',
              style: AppTypography.headingM.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.space6),
            SaProgressRing(
              progress: progress,
              size: 180,
              strokeWidth: 10,
              color: AppColors.coral500,
              label: '$secondsRemaining',
            ),
            const SizedBox(height: AppSpacing.space6),
            Text(
              'Your location and emergency contacts will be notified.',
              style: AppTypography.bodyM.copyWith(color: Colors.white.withValues(alpha: 0.7)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.space8),
            SaButton(label: 'Cancel', variant: SaButtonVariant.secondary, fullWidth: true, onPressed: onCancel),
          ],
        ),
      ),
    );
  }
}
