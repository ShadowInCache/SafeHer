import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/external_actions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/cards/sa_card.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/overlays/sa_toast.dart';
import '../domain/models/helpline.dart';

/// Published emergency helplines, one tap from the dialler.
///
/// The list is explicitly scoped to India and states where the numbers came
/// from — an emergency number shown to the wrong country is worse than no
/// number at all.
class HelplinesScreen extends StatelessWidget {
  const HelplinesScreen({super.key});

  static const _actions = ExternalActions();

  Future<void> _call(BuildContext context, Helpline helpline) async {
    final launched = await _actions.dial(helpline.number);
    if (!launched && context.mounted) {
      showSaToast(
        context,
        message: 'No dialler available — the number is ${helpline.number}',
        type: SaToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final helplines = IndiaHelplines.all;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space2,
                AppSpacing.space2,
                AppSpacing.screenMarginPhone,
                0,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const SaIcon(SaIconGlyph.chevronLeft),
                    onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
                    tooltip: 'Back',
                  ),
                  Expanded(
                    child: Text(
                      'Emergency Help',
                      style: AppTypography.headingM.copyWith(color: onSurface),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.screenMarginPhone),
                children: [
                  Text(
                    'National helplines for India. Verified ${helplines.first.lastVerified} '
                    'against ${helplines.first.source}.',
                    style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: AppSpacing.space4),
                  for (final helpline in helplines) ...[
                    _HelplineCard(helpline: helpline, onCall: () => _call(context, helpline)),
                    const SizedBox(height: AppSpacing.space3),
                  ],
                  const SizedBox(height: AppSpacing.space4),
                  Text(
                    'Outside India these numbers will not connect you to help. '
                    'Use your local emergency number instead.',
                    style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.5)),
                  ),
                  const SizedBox(height: AppSpacing.space6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelplineCard extends StatelessWidget {
  const _HelplineCard({required this.helpline, required this.onCall});

  final Helpline helpline;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final accent = helpline.isPrimary ? AppColors.coral500 : AppColors.violet500;

    return SaCard(
      onTap: onCall,
      semanticsLabel: 'Call ${helpline.name} on ${helpline.number}',
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                helpline.number,
                style: AppTypography.labelM.copyWith(color: accent),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(helpline.name, style: AppTypography.labelL.copyWith(color: onSurface)),
                const SizedBox(height: 2),
                Text(
                  helpline.description,
                  style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
          SaIcon(SaIconGlyph.chevronRight, size: 18, color: onSurface.withValues(alpha: 0.4)),
        ],
      ),
    );
  }
}
