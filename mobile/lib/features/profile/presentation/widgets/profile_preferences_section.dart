import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/local/app_preferences.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/cards/sa_card.dart';
import '../../../../core/detection/detection_status.dart';
import '../../data/profile_providers.dart';

/// Profile > Preferences — AI sensitivity, countdown length, auto-record,
/// and appearance, all persisted immediately on change via
/// [AppPreferences].
///
/// The threat threshold is the exception: it is also sent to the server.
/// SafeHer decides whether to raise an automatic alarm (SRS FR-EMG-02)
/// backend-side, so a threshold living only in Hive was a control that
/// moved and changed nothing.
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
              // What this threshold currently governs, from the server rather
              // than from an assumption. Until a detection model is serving,
              // nothing produces the score this is compared against, and a
              // control that silently governs nothing is indistinguishable
              // from protection.
              const SizedBox(height: AppSpacing.space2),
              _DetectionStatusLine(status: ref.watch(detectionStatusProvider)),
              Slider(
                value: prefs.threatThreshold,
                min: 0.50,
                max: 0.95,
                divisions: 9,
                activeColor: AppColors.violet500,
                label: '${(prefs.threatThreshold * 100).round()}%',
                onChanged: (value) {
                  // Local first, so the slider never lags the finger.
                  prefsNotifier.setThreatThreshold(value);
                  ref.invalidate(appPreferencesProvider);
                },
                onChangeEnd: (value) {
                  // Sent once the user lets go rather than on every frame
                  // of the drag, which would be one PATCH per pixel.
                  unawaited(
                    ref
                        .read(profileRepositoryProvider)
                        .updateProfile(threatThreshold: value),
                  );
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
            color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
            borderRadius: AppRadius.fullRadius,
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.primary : onSurface.withValues(alpha: 0.2),
            ),
          ),
          child: Text(
            '${seconds}s',
            style: AppTypography.labelL.copyWith(
              color: selected ? Theme.of(context).colorScheme.onPrimary : onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// One honest line about whether the threshold above is doing anything.
class _DetectionStatusLine extends StatelessWidget {
  const _DetectionStatusLine({required this.status});

  final AsyncValue<DetectionStatus> status;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return status.when(
      // No placeholder claim while loading. "Checking" is honest; anything
      // more would be a guess in the dangerous direction.
      loading: () => Text(
        'Checking detection status…',
        style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.5)),
      ),
      error: (error, stackTrace) => Text(
        "Couldn't check whether automatic detection is running.",
        style: AppTypography.bodyS.copyWith(color: AppColors.warning500),
      ),
      data: (value) {
        final active = value.autoSosActive;
        return Semantics(
          label: '${value.headline}. ${value.detail}',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6, right: AppSpacing.space2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? AppColors.success500 : AppColors.warning500,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value.headline,
                      style: AppTypography.labelM.copyWith(
                        color: active ? AppColors.success500 : AppColors.warning500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value.detail,
                      style: AppTypography.bodyS.copyWith(
                        color: onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
