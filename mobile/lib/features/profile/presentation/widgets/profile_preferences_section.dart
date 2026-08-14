import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/local/app_preferences.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/cards/sa_card.dart';

/// Profile > Preferences — AI sensitivity, countdown length, auto-record,
/// and appearance, all persisted immediately on change via
/// [AppPreferences].
class ProfilePreferencesSection extends ConsumerWidget {
  const ProfilePreferencesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final prefsNotifier = ref.read(appPreferencesProvider);
    final prefs = ref.watch(appPreferencesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Preferences', style: AppTypography.headingM.copyWith(color: onSurface)),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          semanticsLabel: 'Threat threshold, ${(prefs.threatThreshold * 100).round()} percent',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Threat Threshold', style: AppTypography.headingS.copyWith(color: onSurface))),
                  Text(
                    '${(prefs.threatThreshold * 100).round()}%',
                    style: AppTypography.monoDataS.copyWith(color: AppColors.violet500),
                  ),
                ],
              ),
              Slider(
                value: prefs.threatThreshold,
                min: 0.50,
                max: 0.95,
                divisions: 9,
                activeColor: AppColors.violet500,
                label: '${(prefs.threatThreshold * 100).round()}%',
                onChanged: (value) {
                  prefsNotifier.setThreatThreshold(value);
                  ref.invalidate(appPreferencesProvider);
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Conservative', style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.5))),
                  Text('Sensitive', style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.5))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          semanticsLabel: 'Countdown duration, ${prefs.countdownSeconds} seconds',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Countdown Duration', style: AppTypography.headingS.copyWith(color: onSurface)),
              const SizedBox(height: AppSpacing.space3),
              Row(
                children: [
                  for (final seconds in [5, 10, 15]) ...[
                    _DurationChip(
                      seconds: seconds,
                      selected: prefs.countdownSeconds == seconds,
                      onTap: () {
                        prefsNotifier.setCountdownSeconds(seconds);
                        ref.invalidate(appPreferencesProvider);
                      },
                    ),
                    if (seconds != 15) const SizedBox(width: AppSpacing.space2),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          child: Row(
            children: [
              Expanded(child: Text('Auto-Record on Alert', style: AppTypography.bodyL.copyWith(color: onSurface))),
              Switch(
                value: prefs.autoRecordEnabled,
                activeTrackColor: AppColors.violet500,
                onChanged: (value) {
                  prefsNotifier.setAutoRecordEnabled(value);
                  ref.invalidate(appPreferencesProvider);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space3),
        SaCard(
          child: Row(
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
        ),
      ],
    );
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({required this.seconds, required this.selected, required this.onTap});

  final int seconds;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: '$seconds seconds',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space2),
          decoration: BoxDecoration(
            color: selected ? AppColors.violet500 : Colors.transparent,
            borderRadius: AppRadius.fullRadius,
            border: Border.all(color: selected ? AppColors.violet500 : onSurface.withValues(alpha: 0.2)),
          ),
          child: Text(
            '${seconds}s',
            style: AppTypography.labelL.copyWith(color: selected ? Colors.white : onSurface),
          ),
        ),
      ),
    );
  }
}
