import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/cards/sa_card.dart';
import '../../../../shared/components/icons/sa_icon.dart';
import '../../data/glasses_pairing_controller.dart';
import 'glasses_pairing_sheet.dart';

/// The camera's own row on the Devices screen.
///
/// Separate from the BLE device list because the glasses are not a BLE
/// peripheral — they are an address on the WiFi — so they never appear in
/// `devicesProvider` and would otherwise be invisible. Always shown, paired or
/// not: a camera that has not been connected is a thing the user needs to see,
/// not an absence they have to notice.
class GlassesStatusCard extends ConsumerWidget {
  const GlassesStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(glassesPairingProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final paired = state.isPaired;

    return SaCard(
      child: InkWell(
        onTap: () => showGlassesPairingSheet(context),
        borderRadius: AppRadius.xl2Radius,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space4),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (paired ? AppColors.success500 : AppColors.violet500)
                      .withValues(alpha: 0.12),
                  borderRadius: AppRadius.lgRadius,
                ),
                alignment: Alignment.center,
                child: SaIcon(
                  SaIconGlyph.glasses,
                  size: 22,
                  color: paired ? AppColors.success500 : AppColors.violet500,
                ),
              ),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SafeHer Camera',
                        style: AppTypography.labelL.copyWith(color: onSurface)),
                    const SizedBox(height: AppSpacing.space1),
                    Text(
                      // Names the address rather than saying "Connected",
                      // because the app has not spoken to it since pairing and
                      // a claim of a live link would be one it cannot support.
                      paired
                          ? 'Set up at ${state.host}'
                          : 'Not connected — weapon detection is off',
                      style: AppTypography.bodyS.copyWith(
                        color: onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              SaIcon(
                SaIconGlyph.chevronRight,
                size: 18,
                color: onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
