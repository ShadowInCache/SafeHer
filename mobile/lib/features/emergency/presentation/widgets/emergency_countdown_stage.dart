import 'package:flutter/material.dart';

import '../../../../core/location/location_result.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/buttons/sa_button.dart';
import '../../../../shared/components/feedback/sa_progress_ring.dart';
import '../../../../shared/components/icons/sa_icon.dart';

/// Stage 2 — a cancellable countdown before the alert actually dispatches.
class EmergencyCountdownStage extends StatelessWidget {
  const EmergencyCountdownStage({
    required this.secondsRemaining,
    required this.totalSeconds,
    required this.onCancel,
    this.location,
    super.key,
  });

  final int secondsRemaining;
  final int totalSeconds;
  final VoidCallback onCancel;

  /// Null while the fix is still pending — the location row fades in once
  /// this becomes non-null, whether it's a fix or a graceful failure.
  final LocationResult? location;

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
            const SizedBox(height: AppSpacing.space4),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: location == null ? 0.0 : 1.0,
              child: _LocationStatusRow(location: location),
            ),
            const SizedBox(height: AppSpacing.space6),
            SaButton(label: 'Cancel', variant: SaButtonVariant.secondary, fullWidth: true, onPressed: onCancel),
          ],
        ),
      ),
    );
  }
}

class _LocationStatusRow extends StatelessWidget {
  const _LocationStatusRow({required this.location});

  final LocationResult? location;

  @override
  Widget build(BuildContext context) {
    final loc = location;
    final label = switch (loc) {
      LocationAvailable() => '${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)}',
      LocationUnavailable() => loc.userMessage,
      null => '',
    };
    final locked = loc is LocationAvailable;
    return Semantics(
      label: locked ? 'GPS locked at $label' : label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SaIcon(SaIconGlyph.mapPin, size: 14, color: locked ? AppColors.success500 : Colors.white.withValues(alpha: 0.5)),
          const SizedBox(width: AppSpacing.space2),
          Flexible(
            child: Text(
              label,
              style: AppTypography.monoDataS.copyWith(color: Colors.white.withValues(alpha: 0.7)),
              textAlign: TextAlign.center,
              // Coordinates fit on one line; the no-fix fallback sentence does
              // not, and at one line it ellipsised to "Location unavailable —
              // dispatching w…", which cuts off exactly the half that says the
              // alert is still going out.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
