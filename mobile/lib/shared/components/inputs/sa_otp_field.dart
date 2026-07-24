import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/animations/animation_helpers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_typography.dart';

enum SaOTPFieldStatus { idle, error, success }

/// [length] individually-boxed digit inputs with auto-advance, backspace
/// retreat, and paste distribution. Verification result is driven
/// externally via [status] (the screen owns the async check).
class SaOTPField extends StatefulWidget {
  const SaOTPField({
    required this.onCompleted,
    super.key,
    this.length = 6,
    this.status = SaOTPFieldStatus.idle,
    this.autoFocus = true,
  });

  final int length;
  final ValueChanged<String> onCompleted;
  final SaOTPFieldStatus status;
  final bool autoFocus;

  @override
  State<SaOTPField> createState() => SaOTPFieldState();
}

class SaOTPFieldState extends State<SaOTPField> with SingleTickerProviderStateMixin {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  }

  @override
  void didUpdateWidget(covariant SaOTPField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status == SaOTPFieldStatus.error && oldWidget.status != SaOTPFieldStatus.error) {
      AnimationHelpers.forward(context, _shakeController).then((_) {
        if (mounted) {
          _shakeController.value = 0;
          clear();
        }
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _shakeController.dispose();
    super.dispose();
  }

  /// Clears all boxes and refocuses the first one.
  void clear() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes.first.requestFocus();
  }

  void _handleChanged(int index, String value) {
    if (value.length > 1) {
      // Pasted content: distribute across remaining boxes.
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i < digits.length && index + i < widget.length; i++) {
        _controllers[index + i].text = digits[i];
      }
      final nextIndex = math.min(index + digits.length, widget.length - 1);
      _focusNodes[nextIndex].requestFocus();
      _maybeComplete();
      return;
    }

    if (value.isNotEmpty && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    _maybeComplete();
  }

  void _maybeComplete() {
    final code = _controllers.map((c) => c.text).join();
    if (code.length == widget.length && !code.contains(RegExp(r'\D'))) {
      widget.onCompleted(code);
    }
  }

  void _handleBackspace(int index) {
    if (_controllers[index].text.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
    }
  }

  Color _borderColor(BuildContext context) => switch (widget.status) {
    SaOTPFieldStatus.error => AppColors.coral500,
    SaOTPFieldStatus.success => AppColors.success500,
    SaOTPFieldStatus.idle => Theme.of(context).dividerColor,
  };

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final borderColor = _borderColor(context);

    return Semantics(
      label: '${widget.length}-digit verification code',
      child: AnimatedBuilder(
        animation: _shakeController,
        builder: (context, child) {
          final t = _shakeController.value;
          final shake = math.sin(t * math.pi * 4) * 8 * (1 - t);
          return Transform.translate(offset: Offset(shake, 0), child: child);
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(widget.length, (i) {
            return SizedBox(
              width: 44,
              height: 56,
              child: KeyboardListener(
                focusNode: FocusNode(skipTraversal: true, canRequestFocus: false),
                onKeyEvent: (event) {
                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
                    _handleBackspace(i);
                  }
                },
                child: TextField(
                  controller: _controllers[i],
                  focusNode: _focusNodes[i],
                  autofocus: widget.autoFocus && i == 0,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: widget.length,
                  style: AppTypography.headingL.copyWith(color: onSurface),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                    filled: true,
                    fillColor: Theme.of(context).inputDecorationTheme.fillColor,
                    border: OutlineInputBorder(borderRadius: AppRadius.mdRadius, borderSide: BorderSide(color: borderColor)),
                    enabledBorder: OutlineInputBorder(borderRadius: AppRadius.mdRadius, borderSide: BorderSide(color: borderColor)),
                    focusedBorder: OutlineInputBorder(borderRadius: AppRadius.mdRadius, borderSide: BorderSide(color: borderColor, width: 2)),
                  ),
                  onChanged: (value) => _handleChanged(i, value),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
