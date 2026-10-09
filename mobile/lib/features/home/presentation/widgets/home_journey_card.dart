import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/cards/sa_card.dart';
import '../../../../shared/components/icons/sa_icon.dart';
import '../../../safety/domain/models/safe_journey.dart';

/// Starts a Safe Journey, or opens the one already running.
///
/// Starting a journey is the single most consequential thing a user does in
/// this app — it is what arms the microphone, the camera policy and the glove
/// pipeline, and what gets her contacts told if she does not arrive. It was
/// reachable only through Profile → Settings → Safety Toolkit → Safe Journey,
/// four taps deep behind a settings menu, which is the wrong place for
/// something you reach for as you leave the house.
///
/// Full width rather than a fifth tile in the quick-actions grid: a two-column
/// grid of five leaves an orphan, and this outranks the tiles beside it
/// anyway.
class HomeJourneyCard extends StatelessWidget {
  const HomeJourneyCard({required this.journey, required this.onTap, super.key});

  /// The journey in progress, or null when there is none.
  final SafeJourney? journey;
  final VoidCallback onTap;

  static String _remainingLabel(Duration remaining) {
    if (remaining.isNegative) return 'overdue';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m left';
    return '${remaining.inMinutes + 1}m left';
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final active = journey?.isInProgress ?? false;
    final accent = active ? AppColors.success500 : AppColors.violet500;

    final title = active ? 'Journey active' : 'Start Safe Journey';
    final subtitle = active
        ? '${journey!.destinationLabel} · ${_remainingLabel(journey!.remaining(DateTime.now()))}'
        : 'Watches for trouble and tells your contacts if you don\'t arrive';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
      child: SaCard(
        onTap: onTap,
        useBlur: false,
        semanticsLabel: active ? 'Open your active Safe Journey' : 'Start a Safe Journey',
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: SaIcon(SaIconGlyph.shield, size: 22, color: accent),
            ),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (active) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: AppSpacing.space2),
                      ],
                      Flexible(
                        child: Text(
                          title,
                          style: AppTypography.labelL.copyWith(
                            color: active ? accent : onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space1),
                  Text(
                    subtitle,
                    style: AppTypography.bodyS.copyWith(
                      color: onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.space2),
            SaIcon(
              SaIconGlyph.chevronRight,
              size: 18,
              color: onSurface.withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }
}
