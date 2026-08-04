import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/buttons/sa_sos_button.dart';

/// Stage 1 — idle, hold-to-confirm. [SaSOSButton] owns the actual hold
/// gesture/timing; this just supplies the surrounding copy.
class EmergencyPreActivationStage extends StatelessWidget {
  const EmergencyPreActivationStage({required this.onConfirmed, super.key});

  final VoidCallback onConfirmed;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Emergency SOS',
              style: AppTypography.headingL.copyWith(color: onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              'Hold the button below to alert your emergency contacts and share your location.',
              style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.6)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.space10),
            SaSOSButton(onConfirmed: onConfirmed),
            const SizedBox(height: AppSpacing.space6),
            Text(
              'Hold for 1.2 seconds',
              style: AppTypography.labelM.copyWith(color: onSurface.withValues(alpha: 0.5)),
            ),
          ],
        ),
      ),
    );
  }
}
