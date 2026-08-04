import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/buttons/sa_button.dart';
import '../../../shared/components/cards/sa_card.dart';
import '../../../shared/components/feedback/sa_empty_state.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../data/settings_providers.dart';
import '../domain/models/app_settings.dart';
import 'widgets/sa_settings_toggle.dart';

/// App preferences: notifications, location sharing, biometric lock, an
/// entry point into managing emergency contacts, and sign-out.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsNotifierProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.space2, AppSpacing.space2, AppSpacing.screenMarginPhone, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const SaIcon(SaIconGlyph.chevronLeft),
                    onPressed: () => context.canPop() ? context.pop() : context.go('/profile'),
                    tooltip: 'Back',
                  ),
                  Text('Settings', style: AppTypography.headingM.copyWith(color: onSurface)),
                ],
              ),
            ),
            Expanded(
              child: settingsAsync.when(
                data: (settings) => _SettingsContent(settings: settings),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => SaEmptyState(
                  title: "Couldn't load settings",
                  body: 'Check your connection and try again.',
                  ctaLabel: 'Retry',
                  onCtaTap: () => ref.invalidate(appSettingsNotifierProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsContent extends ConsumerWidget {
  const _SettingsContent({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final notifier = ref.read(appSettingsNotifierProvider.notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenMarginPhone,
        AppSpacing.space2,
        AppSpacing.screenMarginPhone,
        AppSpacing.space8,
      ),
      children: [
        Text('Notifications', style: AppTypography.headingS.copyWith(color: onSurface)),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          child: _SettingsToggleRow(
            label: 'Push Notifications',
            description: 'Alerts, reminders, and device status updates.',
            value: settings.pushNotifications,
            onChanged: notifier.setPushNotifications,
          ),
        ),
        const SizedBox(height: AppSpacing.space5),
        Text('Privacy & Security', style: AppTypography.headingS.copyWith(color: onSurface)),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SettingsToggleRow(
                label: 'Location Sharing',
                description: 'Share live location with emergency contacts during an alert.',
                value: settings.locationSharing,
                onChanged: notifier.setLocationSharing,
              ),
              const Divider(height: AppSpacing.space6),
              _SettingsToggleRow(
                label: 'Biometric Lock',
                description: 'Require Face ID or fingerprint to open the app.',
                value: settings.biometricLock,
                onChanged: notifier.setBiometricLock,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space5),
        Text('Safety', style: AppTypography.headingS.copyWith(color: onSurface)),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          onTap: () => context.go('/settings/contacts'),
          semanticsLabel: 'Emergency Contacts',
          child: Row(
            children: [
              Expanded(
                child: Text('Emergency Contacts', style: AppTypography.bodyL.copyWith(color: onSurface)),
              ),
              SaIcon(SaIconGlyph.chevronRight, size: 18, color: onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space5),
        Text('About', style: AppTypography.headingS.copyWith(color: onSurface)),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          child: Row(
            children: [
              Expanded(
                child: Text('App Version', style: AppTypography.bodyL.copyWith(color: onSurface)),
              ),
              Text('1.0.0', style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.5))),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
        SaButton(
          label: 'Sign Out',
          variant: SaButtonVariant.danger,
          confirmRequired: true,
          fullWidth: true,
          onPressed: () => context.go('/auth/login'),
        ),
      ],
    );
  }
}

class _SettingsToggleRow extends StatelessWidget {
  const _SettingsToggleRow({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: AppTypography.bodyL.copyWith(color: onSurface)),
              const SizedBox(height: AppSpacing.space1),
              Text(description, style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.6))),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.space3),
        SaSettingsToggle(value: value, onChanged: onChanged, semanticsLabel: label),
      ],
    );
  }
}
