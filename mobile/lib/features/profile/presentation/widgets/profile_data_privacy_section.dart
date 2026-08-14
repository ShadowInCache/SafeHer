import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/cards/sa_card.dart';
import '../../../../shared/components/icons/sa_icon.dart';
import '../../../../shared/components/overlays/sa_confirm_dialog.dart';
import '../../../../shared/components/overlays/sa_toast.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../auth/domain/auth_repository.dart';

/// Profile > Data & Privacy — export and account deletion. Deletion
/// requires typing "DELETE" (via [SaConfirmDialog]) before it's armed, and
/// actually calls [AuthRepository.deleteAccount] rather than just
/// navigating away.
class ProfileDataPrivacySection extends ConsumerStatefulWidget {
  const ProfileDataPrivacySection({required this.userDataSummary, super.key});

  /// Plain-text summary of what "download my data" would include — real
  /// data already loaded on this screen, not fabricated.
  final String userDataSummary;

  @override
  ConsumerState<ProfileDataPrivacySection> createState() => _ProfileDataPrivacySectionState();
}

class _ProfileDataPrivacySectionState extends ConsumerState<ProfileDataPrivacySection> {
  bool _deleting = false;

  Future<void> _downloadData(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your Data', style: AppTypography.headingM.copyWith(color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: AppSpacing.space3),
              Text(
                widget.userDataSummary,
                style: AppTypography.bodyM.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: AppSpacing.space4),
              Text(
                'A full export requires a live backend export endpoint, which isn\'t wired up in this build yet.',
                style: AppTypography.bodyS.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final confirmed = await showSaConfirmDialog(
      context,
      title: 'Delete Account',
      message: 'Type "DELETE" to confirm. This permanently removes your account and cannot be undone.',
      confirmPhrase: 'DELETE',
      confirmLabel: 'Delete my account',
    );
    if (!confirmed || !context.mounted) return;

    setState(() => _deleting = true);
    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      if (context.mounted) context.go('/auth/login');
    } on AuthException catch (e) {
      if (context.mounted) showSaToast(context, message: e.message, type: SaToastType.error);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Data & Privacy', style: AppTypography.headingM.copyWith(color: onSurface)),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          semanticsLabel: 'Download my data',
          onTap: () => _downloadData(context),
          child: Row(
            children: [
              const SaIcon(SaIconGlyph.download, size: 20, color: AppColors.violet500),
              const SizedBox(width: AppSpacing.space3),
              Expanded(child: Text('Download My Data', style: AppTypography.bodyL.copyWith(color: onSurface))),
              SaIcon(SaIconGlyph.chevronRight, size: 18, color: onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          semanticsLabel: 'Delete account',
          onTap: _deleting ? null : () => _deleteAccount(context),
          child: Row(
            children: [
              SaIcon(SaIconGlyph.close, size: 20, color: AppColors.coral500),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: Text(
                  _deleting ? 'Deleting…' : 'Delete Account',
                  style: AppTypography.bodyL.copyWith(color: AppColors.coral500, fontWeight: FontWeight.w600),
                ),
              ),
              if (_deleting)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        ),
      ],
    );
  }
}
