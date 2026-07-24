import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../buttons/sa_button.dart';
import '../icons/sa_icon.dart';

/// Illustration + title + body + optional CTA for empty/no-results states.
/// [illustration] defaults to a simple glyph when no Lottie asset is
/// supplied by the caller (screens can pass a Lottie widget once assets
/// are sourced).
class SaEmptyState extends StatelessWidget {
  const SaEmptyState({
    required this.title,
    required this.body,
    super.key,
    this.illustration,
    this.ctaLabel,
    this.onCtaTap,
  });

  final String title;
  final String body;
  final Widget? illustration;
  final String? ctaLabel;
  final VoidCallback? onCtaTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            illustration ??
                const SaIcon(SaIconGlyph.search, size: 64, color: AppColors.violet500),
            const SizedBox(height: AppSpacing.space5),
            Text(title, style: AppTypography.headingL.copyWith(color: onSurface), textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.space2),
            Text(
              body,
              style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.6)),
              textAlign: TextAlign.center,
            ),
            if (ctaLabel != null) ...[
              const SizedBox(height: AppSpacing.space5),
              SaButton(label: ctaLabel!, onPressed: onCtaTap),
            ],
          ],
        ),
      ),
    );
  }
}
