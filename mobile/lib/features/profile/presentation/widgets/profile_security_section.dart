import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/biometrics/biometric_providers.dart';
import '../../../../core/biometrics/biometric_service.dart';
import '../../../../core/local/app_preferences.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/layout/sa_section_header.dart';
import '../../../../shared/components/cards/sa_card.dart';
import '../../../../shared/components/icons/sa_icon.dart';
import '../../../../shared/components/overlays/sa_toast.dart';
import '../../../auth/data/auth_providers.dart';

/// Profile > Security — password reset and the real biometric-unlock
/// toggle (backed by `local_auth`, not a decorative switch).
class ProfileSecuritySection extends ConsumerWidget {
  const ProfileSecuritySection({required this.email, super.key});

  final String email;

  Future<void> _sendPasswordReset(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authRepositoryProvider).sendPasswordResetEmail(email);
      if (context.mounted) showSaToast(context, message: 'Password reset link sent to $email.');
    } catch (_) {
      if (context.mounted) {
        showSaToast(context, message: "Couldn't send reset link. Try again.", type: SaToastType.error);
      }
    }
  }

  Future<void> _toggleBiometric(BuildContext context, WidgetRef ref, bool enable) async {
    final biometrics = ref.read(biometricServiceProvider);
    final prefs = ref.read(appPreferencesProvider);

    if (!enable) {
      await prefs.setBiometricEnabled(false);
      ref.invalidate(appPreferencesProvider);
      return;
    }

    if (!await biometrics.isAvailable) {
      if (context.mounted) {
        showSaToast(
          context,
          message: "This phone doesn't support ${biometrics.platformLabel} unlock.",
          type: SaToastType.error,
        );
      }
      return;
    }

    // Checked separately from `isAvailable`, which only reports that the
    // hardware exists. A reader with nothing enrolled passes that check and
    // then fails at the prompt, which used to surface as "authentication
    // failed" — telling the user to retry the one thing that cannot work.
    if (!await biometrics.hasEnrolledBiometrics) {
      if (context.mounted) {
        showSaToast(
          context,
          message:
              'No ${biometrics.platformLabel.toLowerCase()} is set up on this phone. '
              'Add one in your device settings, then turn this on again.',
          type: SaToastType.error,
        );
      }
      return;
    }

    final result = await biometrics.authenticate(
      reason: 'Enable ${biometrics.platformLabel} unlock for SafeHer',
    );
    if (!context.mounted) return;

    switch (result) {
      case BiometricSuccess():
        await prefs.setBiometricEnabled(true);
        ref.invalidate(appPreferencesProvider);
        if (context.mounted) {
          showSaToast(context, message: '${biometrics.platformLabel} unlock enabled.');
        }
      case BiometricRejected(:final reason):
        // A cancel gets no message. The user dismissed the sheet on purpose
        // and does not need to be told what they just did.
        final message = BiometricRejected(reason).userMessage(biometrics.platformLabel);
        if (message != null) {
          showSaToast(context, message: message, type: SaToastType.error);
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final prefs = ref.watch(appPreferencesProvider);
    final biometrics = ref.read(biometricServiceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SaSectionHeader(label: 'Security'),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          semanticsLabel: 'Change password',
          onTap: () => _sendPasswordReset(context, ref),
          child: Row(
            children: [
              const SaIcon(SaIconGlyph.check, size: 20, color: AppColors.violet500),
              const SizedBox(width: AppSpacing.space3),
              Expanded(child: Text('Change Password', style: AppTypography.bodyL.copyWith(color: onSurface))),
              SaIcon(SaIconGlyph.chevronRight, size: 18, color: onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          semanticsLabel: '${biometrics.platformLabel} unlock, ${prefs.biometricEnabled ? "on" : "off"}',
          child: Row(
            children: [
              const SaIcon(SaIconGlyph.shield, size: 20, color: AppColors.violet500),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Biometric Unlock', style: AppTypography.bodyL.copyWith(color: onSurface)),
                    Text(
                      biometrics.platformLabel,
                      style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.5)),
                    ),
                  ],
                ),
              ),
              Switch(
                value: prefs.biometricEnabled,
                onChanged: (value) => _toggleBiometric(context, ref, value),
                activeTrackColor: AppColors.violet500,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
