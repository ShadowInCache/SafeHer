import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/cards/sa_card.dart';
import '../../../../shared/components/icons/sa_icon.dart';

class HomeQuickActionsGrid extends StatelessWidget {
  const HomeQuickActionsGrid({
    required this.onSos,
    required this.onCallContact,
    required this.onShareLocation,
    required this.onFindHelp,
    super.key,
  });

  final VoidCallback onSos;
  final VoidCallback onCallContact;
  final VoidCallback onShareLocation;

  /// Opens Nearby Safety. Replaced a "Record Evidence" tile that only ever
  /// showed a toast claiming recording had started — there is no capture
  /// pipeline behind it, so the tile was claiming a capability the app
  /// doesn't have.
  final VoidCallback onFindHelp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AppSpacing.space3,
        crossAxisSpacing: AppSpacing.space3,
        childAspectRatio: 1.6,
        children: [
          _QuickActionCard(label: 'SOS', glyph: SaIconGlyph.shield, onTap: onSos, tinted: true),
          _QuickActionCard(label: 'Call Contact', glyph: SaIconGlyph.profile, onTap: onCallContact),
          _QuickActionCard(label: 'Share Location', glyph: SaIconGlyph.mapPin, onTap: onShareLocation),
          _QuickActionCard(label: 'Find Help', glyph: SaIconGlyph.mapPin, onTap: onFindHelp),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.label, required this.glyph, required this.onTap, this.tinted = false});

  final String label;
  final SaIconGlyph glyph;
  final VoidCallback onTap;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SaCard(
      onTap: onTap,
      useBlur: false,
      semanticsLabel: label,
      child: Container(
        decoration: tinted
            ? BoxDecoration(
                color: AppColors.coral500.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              )
            : null,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SaIcon(glyph, size: 24, color: tinted ? AppColors.coral500 : AppColors.violet500),
            const SizedBox(height: AppSpacing.space2),
            Text(
              label,
              style: AppTypography.labelL.copyWith(color: tinted ? AppColors.coral500 : onSurface),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
