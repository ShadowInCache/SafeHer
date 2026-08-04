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
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}
