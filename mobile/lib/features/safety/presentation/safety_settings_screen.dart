import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/sensors/shake_detector.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/voice/voice_command.dart';
import '../../../shared/components/cards/sa_card.dart';
import '../../../shared/components/feedback/sa_empty_state.dart';
import '../../../shared/components/feedback/sa_loading_shimmer.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/overlays/sa_toast.dart';
import '../data/safety_providers.dart';
import '../domain/models/safety_settings.dart';

/// Safety triggers and the cancel PIN.
///
/// Every switch here is off by default. A trigger the user never chose must
/// never fire, so nothing on this screen is opt-out.
class SafetySettingsScreen extends ConsumerWidget {
  const SafetySettingsScreen({super.key});

  Future<void> _update(
    BuildContext context,
    WidgetRef ref,
    SafetyPreferences updated,
  ) async {
    try {
      await ref.read(safetyPreferencesNotifierProvider.notifier).save(updated);
    } catch (_) {
      if (context.mounted) {
        showSaToast(
          context,
          message: 'Set a Safety PIN first to use that',
          type: SaToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final prefsAsync = ref.watch(safetyPreferencesNotifierProvider);
    final pinAsync = ref.watch(safetyPinStatusNotifierProvider);

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
                    onPressed: () => context.canPop() ? context.pop() : context.go('/settings'),
                    tooltip: 'Back',
                  ),
                  Expanded(
                    child: Text(
                      'Safety Triggers',
                      style: AppTypography.headingM.copyWith(color: onSurface),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: prefsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.screenMarginPhone),
                  child: SaLoadingShimmer(child: SizedBox(height: 260, width: double.infinity)),
                ),
                error: (_, __) => SaEmptyState(
                  title: "Couldn't load your safety settings",
                  body: 'Check your connection and try again.',
                  ctaLabel: 'Retry',
                  onCtaTap: () => ref.invalidate(safetyPreferencesNotifierProvider),
                ),
                data: (prefs) => ListView(
                  padding: const EdgeInsets.all(AppSpacing.screenMarginPhone),
                  children: [
                    _SectionLabel('Emergency Cancel PIN'),
                    SaCard(
                      child: Column(
                        children: [
                          _NavRow(
                            label: pinAsync.valueOrNull?.isSet ?? false
                                ? 'Change Safety PIN'
                                : 'Create Safety PIN',
                            onTap: () => context.go('/settings/safety/pin'),
                          ),
                          const Divider(height: AppSpacing.space5),
                          _SwitchRow(
                            label: 'Require PIN to cancel an alert',
                            description:
                                'A triggered SOS can only be stood down with your PIN. '
                                'Protects against someone else cancelling it for you.',
                            value: prefs.requirePinToCancel,
                            onChanged: (value) => _update(
                              context,
                              ref,
                              prefs.copyWith(requirePinToCancel: value),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space5),
                    _SectionLabel('Shake to trigger SOS'),
                    SaCard(
                      child: Column(
                        children: [
                          _SwitchRow(
                            label: 'Shake trigger',
                            description:
                                'A fallback for when your Smart Glove isn\'t worn or connected. '
                                'Needs three deliberate shakes in a row, then opens the SOS '
                                'countdown — it never dispatches instantly.',
                            value: prefs.shakeTriggerEnabled,
                            onChanged: (value) => _update(
                              context,
                              ref,
                              prefs.copyWith(shakeTriggerEnabled: value),
                            ),
                          ),
                          if (prefs.shakeTriggerEnabled) ...[
                            const Divider(height: AppSpacing.space5),
                            _SensitivityRow(
                              value: ShakeSensitivity.fromLevel(prefs.shakeSensitivity),
                              onChanged: (sensitivity) => _update(
                                context,
                                ref,
                                prefs.copyWith(shakeSensitivity: sensitivity.level),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space5),
                    _SectionLabel('Voice commands'),
                    SaCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SwitchRow(
                            label: 'Voice commands',
                            description:
                                'Recognised on-device and matched against a fixed list. '
                                'Nothing is recorded, stored, or uploaded.',
                            value: prefs.voiceCommandsEnabled,
                            onChanged: (value) => _update(
                              context,
                              ref,
                              prefs.copyWith(voiceCommandsEnabled: value),
                            ),
                          ),
                          if (prefs.voiceCommandsEnabled) ...[
                            const Divider(height: AppSpacing.space5),
                            Text(
                              'Recognised phrases',
                              style: AppTypography.labelM.copyWith(color: onSurface),
                            ),
                            const SizedBox(height: AppSpacing.space2),
                            for (final command in VoiceCommand.values)
                              Padding(
                                padding: const EdgeInsets.only(bottom: AppSpacing.space1),
                                child: Text(
                                  '${command.label} — ${command.spokenExample}',
                                  style: AppTypography.bodyS.copyWith(
                                    color: onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space5),
                    _SectionLabel('Safe Journey'),
                    SaCard(
                      child: _SwitchRow(
                        label: 'Share location during a journey',
                        description:
                                'Posts your real position periodically while a journey is '
                                'active, so contacts can be told where you were last seen.',
                        value: prefs.journeyAutoShareLocation,
                        onChanged: (value) => _update(
                          context,
                          ref,
                          prefs.copyWith(journeyAutoShareLocation: value),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space6),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space2, left: AppSpacing.space1),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.labelM.copyWith(
          color: onSurface.withValues(alpha: 0.5),
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
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
            children: [
              Text(label, style: AppTypography.bodyM.copyWith(color: onSurface)),
              const SizedBox(height: 2),
              Text(
                description,
                style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.55)),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.space3),
        Semantics(
          label: label,
          toggled: value,
          child: Switch(value: value, onChanged: onChanged),
        ),
      ],
    );
  }
}

class _SensitivityRow extends StatelessWidget {
  const _SensitivityRow({required this.value, required this.onChanged});

  final ShakeSensitivity value;
  final ValueChanged<ShakeSensitivity> onChanged;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sensitivity', style: AppTypography.bodyM.copyWith(color: onSurface)),
        const SizedBox(height: AppSpacing.space2),
        SegmentedButton<ShakeSensitivity>(
          segments: [
            for (final sensitivity in ShakeSensitivity.values)
              ButtonSegment(value: sensitivity, label: Text(sensitivity.label.split(' — ').first)),
          ],
          selected: {value},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(
          value.label,
          style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.55)),
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space2),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: AppTypography.bodyM.copyWith(color: onSurface)),
            ),
            SaIcon(SaIconGlyph.chevronRight, size: 18, color: onSurface.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}
