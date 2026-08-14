import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/location/location_providers.dart';
import '../../../core/location/location_result.dart';
import '../../../core/platform/external_actions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/voice/voice_command.dart';
import '../../../shared/components/cards/sa_card.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/overlays/sa_bottom_sheet.dart';
import '../../../shared/components/overlays/sa_toast.dart';
import '../../contacts/data/contacts_providers.dart';
import '../data/safety_providers.dart';
import 'widgets/voice_command_sheet.dart';

/// One entry point for the phone-side safety tools, so they live together
/// instead of being scattered across the app.
class SafetyToolkitScreen extends ConsumerWidget {
  const SafetyToolkitScreen({super.key});

  static const _actions = ExternalActions();

  Future<void> _openVoiceCommands(BuildContext context, WidgetRef ref) async {
    final enabled =
        ref.read(safetyPreferencesNotifierProvider).valueOrNull?.voiceCommandsEnabled ?? false;
    if (!enabled) {
      showSaToast(
        context,
        message: 'Turn on voice commands in Safety Triggers first',
        type: SaToastType.info,
      );
      return;
    }

    final command = await showSaBottomSheet<VoiceCommand>(
      context,
      builder: (context) => const VoiceCommandSheet(),
    );
    if (command == null || !context.mounted) return;
    await handleVoiceCommand(context, ref, command);
  }

  /// Applies a recognised command. Critical actions keep every guard they
  /// have elsewhere: SOS opens the countdown rather than dispatching, and
  /// cancelling is routed through the emergency screen so the PIN gate still
  /// applies — voice never bypasses a confirmation step.
  static Future<void> handleVoiceCommand(
    BuildContext context,
    WidgetRef ref,
    VoiceCommand command,
  ) async {
    switch (command) {
      case VoiceCommand.startSos:
        context.go('/emergency?auto=1');
      case VoiceCommand.cancelSos:
        // Cancelling is only meaningful inside the emergency flow, where the
        // PIN requirement is enforced.
        context.go('/emergency');
      case VoiceCommand.showNearbyHelp:
        context.go('/safety/nearby');
      case VoiceCommand.startJourney:
        context.go('/safety/journey');
      case VoiceCommand.callPrimaryContact:
        await _callPrimaryContact(context, ref);
      case VoiceCommand.shareLocation:
        await _shareLocation(context, ref);
    }
  }

  static Future<void> _callPrimaryContact(BuildContext context, WidgetRef ref) async {
    final contacts = ref.read(contactsNotifierProvider).valueOrNull ?? const [];
    if (contacts.isEmpty) {
      if (context.mounted) {
        showSaToast(
          context,
          message: 'No emergency contacts yet — add one in Settings',
          type: SaToastType.info,
        );
      }
      return;
    }

    final primary = contacts.reduce((a, b) => a.priority <= b.priority ? a : b);
    final launched = await _actions.dial(primary.phone);
    if (!launched && context.mounted) {
      showSaToast(context, message: 'No dialler available', type: SaToastType.error);
    }
  }

  static Future<void> _shareLocation(BuildContext context, WidgetRef ref) async {
    final fix = await ref.read(locationServiceProvider).getCurrentLocation();
    if (!context.mounted) return;

    if (fix is! LocationAvailable) {
      showSaToast(context, message: (fix as LocationUnavailable).userMessage, type: SaToastType.error);
      return;
    }

    final contacts = ref.read(contactsNotifierProvider).valueOrNull ?? const [];
    if (contacts.isEmpty) {
      showSaToast(
        context,
        message: 'No emergency contacts yet — add one in Settings',
        type: SaToastType.info,
      );
      return;
    }

    final primary = contacts.reduce((a, b) => a.priority <= b.priority ? a : b);
    final mapsLink = 'https://www.google.com/maps/search/?api=1&query='
        '${fix.latitude},${fix.longitude}';
    final launched = await _actions.sendSms(
      primary.phone,
      body: 'My current location: $mapsLink',
    );
    if (!launched && context.mounted) {
      showSaToast(context, message: 'No messaging app available', type: SaToastType.error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

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
                      'Safety Toolkit',
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
                  _ToolRow(
                    glyph: SaIconGlyph.mapPin,
                    accent: AppColors.violet500,
                    title: 'Nearby Safety',
                    subtitle: 'Real police, hospitals and transit around you',
                    onTap: () => context.go('/safety/nearby'),
                  ),
                  _ToolRow(
                    glyph: SaIconGlyph.shield,
                    accent: AppColors.success500,
                    title: 'Safe Journey',
                    subtitle: 'Share a trip with contacts until you arrive',
                    onTap: () => context.go('/safety/journey'),
                  ),
                  _ToolRow(
                    glyph: SaIconGlyph.bell,
                    accent: AppColors.coral500,
                    title: 'Emergency Help',
                    subtitle: 'Published national helplines, one tap to call',
                    onTap: () => context.go('/safety/helplines'),
                  ),
                  _ToolRow(
                    glyph: SaIconGlyph.mic,
                    accent: AppColors.info500,
                    title: 'Voice command',
                    subtitle: 'Speak a command instead of tapping',
                    onTap: () => _openVoiceCommands(context, ref),
                  ),
                  _ToolRow(
                    glyph: SaIconGlyph.ring,
                    accent: AppColors.warning500,
                    title: 'Fake Call',
                    subtitle: 'Schedule a call to give yourself an exit',
                    onTap: () => context.go('/safety/fake-call'),
                  ),
                  _ToolRow(
                    glyph: SaIconGlyph.eye,
                    accent: AppColors.violet400,
                    title: 'Safety & Awareness',
                    subtitle: 'Short guides, including self-defence awareness',
                    onTap: () => context.go('/safety/guides'),
                  ),
                  const SizedBox(height: AppSpacing.space4),
                  _ToolRow(
                    glyph: SaIconGlyph.shield,
                    accent: AppColors.neutral400,
                    title: 'Safety Triggers',
                    subtitle: 'Shake, voice, and your Emergency Cancel PIN',
                    onTap: () => context.go('/settings/safety'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.glyph,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final SaIconGlyph glyph;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space3),
      child: SaCard(
        onTap: onTap,
        semanticsLabel: title,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: SaIcon(glyph, size: 22, color: accent)),
            ),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.labelL.copyWith(color: onSurface)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            SaIcon(SaIconGlyph.chevronRight, size: 18, color: onSurface.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}
