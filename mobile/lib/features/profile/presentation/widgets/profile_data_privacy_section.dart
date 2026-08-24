import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/platform/report_export.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/layout/sa_section_header.dart';
import '../../../../shared/components/cards/sa_card.dart';
import '../../../../shared/components/icons/sa_icon.dart';
import '../../../../shared/components/overlays/sa_confirm_dialog.dart';
import '../../../../shared/components/overlays/sa_toast.dart';
import '../../../auth/data/auth_providers.dart';
import '../../../auth/domain/auth_repository.dart';
import '../../../../shared/utils/user_error.dart';
import '../../data/profile_providers.dart';

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
  bool _exporting = false;

  /// Matches how the rest of the app hands a document to the user — the
  /// system share sheet, with no copy left behind in app storage.
  static const _export = ReportExport();

  /// Fetches the account's data and hands it to the share sheet.
  ///
  /// This used to open a sheet that summarised what an export *would*
  /// contain and admitted no endpoint existed. `GET /users/me/export` now
  /// does, so the button does what its label says: account, contacts,
  /// devices, incidents, locations, journeys and the notification log, as
  /// one JSON document.
  ///
  /// Evidence recordings are referenced by id and download URL rather than
  /// embedded — they are encrypted at rest for a reason, and inlining an
  /// assault recording into a file bound for a Downloads folder would undo
  /// it.
  Future<void> _downloadData(BuildContext context) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await ref.read(profileRepositoryProvider).exportMyData();
      if (!context.mounted) return;

      if (bytes.isEmpty) {
        showSaToast(
          context,
          message: 'The export came back empty. Please try again.',
          type: SaToastType.error,
        );
        return;
      }

      final stamp = DateTime.now().toIso8601String().split('T').first;
      final shared = await _export.shareBytes(
        bytes: Uint8List.fromList(bytes),
        filename: 'safeher-data-$stamp.json',
        mimeType: 'application/json',
        subject: 'My SafeHer data',
      );
      if (!context.mounted) return;
      if (!shared) {
        // Never fails silently: a button that appears to do nothing is what
        // this whole change is replacing.
        showSaToast(
          context,
          message: "Couldn't open the share sheet on this device.",
          type: SaToastType.error,
        );
      }
    } catch (error) {
      if (context.mounted) {
        showSaToast(
          context,
          // describeError maps a 404 on this route to "Server needs
          // updating", which is exactly right here: the export endpoint is
          // new, and the most likely failure is an app talking to a backend
          // that has not been redeployed yet.
          message: describeError(
            error,
            fallbackTitle: "Couldn't prepare your data export",
          ).message,
          type: SaToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
        const SaSectionHeader(label: 'Data & Privacy'),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          semanticsLabel: 'Download my data',
          onTap: _exporting ? null : () => _downloadData(context),
          child: Row(
            children: [
              const SaIcon(SaIconGlyph.download, size: 20, color: AppColors.violet500),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: Text(
                  _exporting ? 'Preparing your data…' : 'Download My Data',
                  style: AppTypography.bodyL.copyWith(color: onSurface),
                ),
              ),
              if (_exporting)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else
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
