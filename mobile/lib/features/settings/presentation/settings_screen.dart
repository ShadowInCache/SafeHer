import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/session/session_reset.dart';
import '../../../core/local/app_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/buttons/sa_button.dart';
import '../../../shared/components/cards/sa_card.dart';
import '../../../shared/components/feedback/sa_empty_state.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/overlays/sa_confirm_dialog.dart';
import '../../../shared/components/overlays/sa_toast.dart';
import '../../auth/data/auth_providers.dart';
import '../../auth/domain/auth_repository.dart';
import '../data/settings_providers.dart';
import '../domain/models/app_settings.dart';
import 'widgets/sa_settings_toggle.dart';

/// App-wide configuration: account/device entry points, per-channel
/// notification toggles, appearance, about, and account-destructive
/// actions. Screens/preferences that are genuinely per-user safety
/// settings (threat threshold, countdown, biometric) live on Profile —
/// this screen links to them rather than duplicating them.
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

class _SettingsContent extends ConsumerStatefulWidget {
  const _SettingsContent({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends ConsumerState<_SettingsContent> {
  bool _deleting = false;

  Future<void> _signOut(BuildContext context) async {
    try {
      await ref.read(authRepositoryProvider).signOut();
      // Forget the signed-out account's cached data. Without this the
      // next person to sign in sees the previous one's emergency
      // contacts, because those providers are keepAlive.
      if (context.mounted) resetSessionScopedState(ref);
    } catch (_) {
      // Proceeds regardless — see ProfileScreen's Sign Out for the same call.
    }
    if (context.mounted) context.go('/auth/login');
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
    final notifier = ref.read(appSettingsNotifierProvider.notifier);
    final settings = widget.settings;
    final prefsNotifier = ref.read(appPreferencesProvider);
    final prefs = ref.watch(appPreferencesProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenMarginPhone,
        AppSpacing.space2,
        AppSpacing.screenMarginPhone,
        AppSpacing.space8,
      ),
      children: [
        Text('Account', style: AppTypography.headingS.copyWith(color: onSurface)),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NavRow(label: 'Profile', onTap: () => context.go('/profile')),
              const Divider(height: AppSpacing.space6),
              _NavRow(label: 'Emergency Contacts', onTap: () => context.go('/settings/contacts')),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space5),
        Text('Safety', style: AppTypography.headingS.copyWith(color: onSurface)),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NavRow(label: 'Safety Toolkit', onTap: () => context.go('/safety')),
              const Divider(height: AppSpacing.space6),
              _NavRow(label: 'Safety Triggers', onTap: () => context.go('/settings/safety')),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space5),
        Text('Devices', style: AppTypography.headingS.copyWith(color: onSurface)),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          semanticsLabel: 'Paired Devices',
          onTap: () => context.go('/devices'),
          child: Row(
            children: [
              Expanded(child: Text('Paired Devices', style: AppTypography.bodyL.copyWith(color: onSurface))),
              SaIcon(SaIconGlyph.chevronRight, size: 18, color: onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space5),
        Text('Notifications', style: AppTypography.headingS.copyWith(color: onSurface)),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SettingsToggleRow(
                label: 'Push Notifications',
                description: 'Alerts, reminders, and device status updates.',
                value: settings.pushNotifications,
                onChanged: notifier.setPushNotifications,
              ),
              const Divider(height: AppSpacing.space6),
              _SettingsToggleRow(
                label: 'SMS Notifications',
                description: 'Text message alerts when the app is closed.',
                value: settings.smsNotifications,
                onChanged: notifier.setSmsNotifications,
              ),
              const Divider(height: AppSpacing.space6),
              _SettingsToggleRow(
                label: 'Email Notifications',
                description: 'Weekly safety summaries and account emails.',
                value: settings.emailNotifications,
                onChanged: notifier.setEmailNotifications,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space5),
        Text('AI & Safety', style: AppTypography.headingS.copyWith(color: onSurface)),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          child: _SettingsToggleRow(
            label: 'Location Sharing',
            description: 'Share live location with emergency contacts during an alert.',
            value: settings.locationSharing,
            onChanged: notifier.setLocationSharing,
          ),
        ),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          semanticsLabel: 'Threat threshold, ${(prefs.threatThreshold * 100).round()} percent, manage in Profile',
          onTap: () => context.go('/profile'),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Threat Threshold', style: AppTypography.bodyL.copyWith(color: onSurface)),
                    Text(
                      '${(prefs.threatThreshold * 100).round()}% · manage in Profile',
                      style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.5)),
                    ),
                  ],
                ),
              ),
              SaIcon(SaIconGlyph.chevronRight, size: 18, color: onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space5),
        Text('Appearance', style: AppTypography.headingS.copyWith(color: onSurface)),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Dark Mode', style: AppTypography.bodyL.copyWith(color: onSurface))),
                  Switch(
                    value: prefs.darkModeEnabled,
                    activeTrackColor: AppColors.violet500,
                    onChanged: (value) {
                      prefsNotifier.setDarkModeEnabled(value);
                      ref.invalidate(appPreferencesProvider);
                    },
                  ),
                ],
              ),
              const Divider(height: AppSpacing.space6),
              Row(
                children: [
                  Expanded(child: Text('Language', style: AppTypography.bodyL.copyWith(color: onSurface))),
                  Text(
                    'English (US)',
                    style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space5),
        Text('About', style: AppTypography.headingS.copyWith(color: onSurface)),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text('App Version', style: AppTypography.bodyL.copyWith(color: onSurface))),
                  Text('1.0.0', style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.5))),
                ],
              ),
              const Divider(height: AppSpacing.space6),
              _NavRow(
                label: 'Open Source Licenses',
                onTap: () => showLicensePage(context: context, applicationName: 'SafeHer'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space5),
        Text('Danger Zone', style: AppTypography.headingS.copyWith(color: AppColors.coral500)),
        const SizedBox(height: AppSpacing.space3),
        SaButton(
          label: 'Sign Out',
          variant: SaButtonVariant.danger,
          confirmRequired: true,
          fullWidth: true,
          onPressed: () => _signOut(context),
        ),
        const SizedBox(height: AppSpacing.space3),
        SaButton(
          label: _deleting ? 'Deleting…' : 'Delete Account',
          variant: SaButtonVariant.danger,
          fullWidth: true,
          isLoading: _deleting,
          onPressed: _deleting ? null : () => _deleteAccount(context),
        ),
      ],
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppTypography.bodyL.copyWith(color: onSurface))),
            SaIcon(SaIconGlyph.chevronRight, size: 18, color: onSurface.withValues(alpha: 0.4)),
          ],
        ),
      ),
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
