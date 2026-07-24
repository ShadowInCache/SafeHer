import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/animations/animation_helpers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_typography.dart';
import '../icons/sa_icon.dart';

/// Text field with an animated floating label, focus glow ring, shake +
/// coral border on error, and a checkmark fade-in when [isValid].
class SaTextField extends StatefulWidget {
  const SaTextField({
    required this.label,
    super.key,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.errorText,
    this.isValid = false,
    this.prefixIcon,
    this.suffixIcon,
    this.semanticsLabel,
    this.autofillHints,
    this.enabled = true,
  });

  final String label;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? errorText;
  final bool isValid;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? semanticsLabel;
  final Iterable<String>? autofillHints;
  final bool enabled;

  @override
  State<SaTextField> createState() => _SaTextFieldState();
}

class _SaTextFieldState extends State<SaTextField> with SingleTickerProviderStateMixin {
  late final FocusNode _focusNode;
  late final AnimationController _shakeController;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_handleFocusChange);
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  }

  @override
  void didUpdateWidget(covariant SaTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.errorText != null && oldWidget.errorText == null) {
      AnimationHelpers.forward(context, _shakeController).then((_) {
        if (mounted) _shakeController.value = 0;
      });
    }
  }

  void _handleFocusChange() {
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final hasError = widget.errorText != null;
    final borderColor = hasError ? AppColors.coral500 : (widget.isValid ? AppColors.success500 : AppColors.violet500);

    return Semantics(
      label: widget.semanticsLabel ?? widget.label,
      textField: true,
      child: AnimatedBuilder(
        animation: _shakeController,
        builder: (context, child) {
          final t = _shakeController.value;
          final shake = math.sin(t * math.pi * 4) * 6 * (1 - t);
          return Transform.translate(offset: Offset(shake, 0), child: child);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            borderRadius: AppRadius.mdRadius,
            boxShadow: _focused
                ? [BoxShadow(color: borderColor.withValues(alpha: 0.25), blurRadius: 6, spreadRadius: 2)]
                : null,
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            autofillHints: widget.autofillHints,
            enabled: widget.enabled,
            style: AppTypography.bodyL.copyWith(color: onSurface),
            decoration: InputDecoration(
              labelText: widget.label,
              floatingLabelBehavior: FloatingLabelBehavior.auto,
              errorText: widget.errorText,
              prefixIcon: widget.prefixIcon,
              suffixIcon: widget.isValid && !hasError
                  ? AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: 1,
                      child: const SaIcon(SaIconGlyph.check, color: AppColors.success500, size: 20),
                    )
                  : widget.suffixIcon,
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.mdRadius,
                borderSide: BorderSide(color: borderColor, width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.mdRadius,
                borderSide: BorderSide(color: widget.isValid ? AppColors.success500 : Theme.of(context).dividerColor, width: 1),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: AppRadius.mdRadius,
                borderSide: const BorderSide(color: AppColors.coral500, width: 1),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: AppRadius.mdRadius,
                borderSide: const BorderSide(color: AppColors.coral500, width: 2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
