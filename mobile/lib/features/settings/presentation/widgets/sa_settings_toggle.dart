import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/animations/animation_helpers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_extensions.dart';

/// A small custom pill toggle — this app never uses Material's default
/// [Switch]. Mirrors [Switch]'s semantics (toggleable, checked state) so
/// it reads correctly to assistive tech.
class SaSettingsToggle extends StatelessWidget {
  const SaSettingsToggle({required this.value, required this.onChanged, super.key, this.semanticsLabel});

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    final reducedMotion = AnimationHelpers.reducedMotion(context);
    return Semantics(
      label: semanticsLabel,
      toggled: value,
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!value);
        },
        child: AnimatedContainer(
          duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 150),
          width: 44,
          height: 26,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? AppColors.violet500 : saColors.surfaceHighest,
            borderRadius: BorderRadius.circular(13),
          ),
          child: AnimatedAlign(
            duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            // The thumb has to contrast with the track in both states, and
            // the off-state track is surfaceHighest -- which on the light
            // theme is #FAF8F4. A white thumb on it came to 1.03:1, so every
            // toggle in Settings looked like it had no thumb at all until you
            // switched it on.
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: value ? AppColors.neutral50 : saColors.inkMuted,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
