import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../buttons/sa_icon_button.dart';
import '../icons/sa_icon.dart';
import 'sa_text_field.dart';

/// 0 (empty/too short) .. 4 (12+ chars, mixed case, digit, special).
int computePasswordStrength(String password) {
  if (password.length < 8) return password.isEmpty ? 0 : 1;
  final hasSpecial = RegExp(r'[!@#$%^&*(),.?":{}|<>_\-\[\]/\\+=~`]').hasMatch(password);
  final hasUpper = RegExp('[A-Z]').hasMatch(password);
  final hasLower = RegExp('[a-z]').hasMatch(password);
  final hasDigit = RegExp(r'\d').hasMatch(password);

  if (password.length >= 12 && hasUpper && hasLower && hasSpecial && hasDigit) return 4;
  if (hasSpecial) return 3;
  return 2;
}

/// SaTextField specialized for passwords: obscure/reveal toggle plus an
/// optional 4-segment strength meter (weak→red, fair→orange, good→yellow,
/// strong→green + checkmark).
class SaPasswordField extends StatefulWidget {
  const SaPasswordField({
    required this.label,
    super.key,
    this.controller,
    this.onChanged,
    this.errorText,
    this.showStrengthBar = false,
    this.semanticsLabel,
  });

  final String label;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final bool showStrengthBar;
  final String? semanticsLabel;

  @override
  State<SaPasswordField> createState() => _SaPasswordFieldState();
}

class _SaPasswordFieldState extends State<SaPasswordField> {
  bool _obscured = true;
  int _strength = 0;

  static const _strengthColors = [
    AppColors.neutral500,
    AppColors.danger500,
    AppColors.warning500,
    AppColors.warning500,
    AppColors.success500,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SaTextField(
          label: widget.label,
          controller: widget.controller,
          obscureText: _obscured,
          errorText: widget.errorText,
          semanticsLabel: widget.semanticsLabel,
          isValid: widget.showStrengthBar && _strength == 4,
          onChanged: (value) {
            if (widget.showStrengthBar) {
              setState(() => _strength = computePasswordStrength(value));
            }
            widget.onChanged?.call(value);
          },
          suffixIcon: SaIconButton(
            icon: SaIcon(_obscured ? SaIconGlyph.eye : SaIconGlyph.eyeOff, size: 18),
            semanticsLabel: _obscured ? 'Show password' : 'Hide password',
            size: SaIconButtonSize.small,
            onPressed: () => setState(() => _obscured = !_obscured),
          ),
        ),
        if (widget.showStrengthBar) ...[
          const SizedBox(height: AppSpacing.space2),
          Row(
            children: List.generate(4, (i) {
              final filled = i < _strength;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 3 ? 4 : 0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 4,
                    decoration: BoxDecoration(
                      color: filled ? _strengthColors[_strength] : AppColors.neutral700,
                      borderRadius: AppRadius.fullRadius,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}
