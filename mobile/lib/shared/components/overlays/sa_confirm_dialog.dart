import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_extensions.dart';
import '../buttons/sa_button.dart';
import '../inputs/sa_text_field.dart';

/// Two-step destructive confirmation: the user must type [confirmPhrase]
/// exactly before the confirm button enables. Returns true if confirmed,
/// false/null otherwise.
class SaConfirmDialog extends StatefulWidget {
  const SaConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmPhrase,
    super.key,
    this.confirmLabel = 'Delete',
  });

  final String title;
  final String message;
  final String confirmPhrase;
  final String confirmLabel;

  @override
  State<SaConfirmDialog> createState() => _SaConfirmDialogState();
}

class _SaConfirmDialogState extends State<SaConfirmDialog> {
  final _controller = TextEditingController();
  bool _matches = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: saColors.surfaceElevated,
        borderRadius: AppRadius.xl2Radius,
        border: Border.all(color: saColors.glassBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: AppTypography.headingL.copyWith(color: onSurface)),
          const SizedBox(height: AppSpacing.space2),
          Text(widget.message, style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.7))),
          const SizedBox(height: AppSpacing.space4),
          Text(
            'Type "${widget.confirmPhrase}" to confirm',
            style: AppTypography.labelM.copyWith(color: onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: AppSpacing.space2),
          SaTextField(
            label: widget.confirmPhrase,
            controller: _controller,
            semanticsLabel: 'Type ${widget.confirmPhrase} to confirm',
            onChanged: (value) => setState(() => _matches = value == widget.confirmPhrase),
          ),
          const SizedBox(height: AppSpacing.space5),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SaButton(
                label: 'Cancel',
                size: SaButtonSize.sm,
                variant: SaButtonVariant.ghost,
                onPressed: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(width: AppSpacing.space2),
              SaButton(
                label: widget.confirmLabel,
                size: SaButtonSize.sm,
                variant: SaButtonVariant.danger,
                onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Presents [SaConfirmDialog] and returns true only if the user typed the
/// exact confirm phrase and tapped confirm.
Future<bool> showSaConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmPhrase,
  String confirmLabel = 'Delete',
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return Material(
        type: MaterialType.transparency,
        child: Center(
          child: SaConfirmDialog(
            title: title,
            message: message,
            confirmPhrase: confirmPhrase,
            confirmLabel: confirmLabel,
          ),
        ),
      );
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8 * animation.value, sigmaY: 8 * animation.value),
        child: FadeTransition(opacity: animation, child: child),
      );
    },
  );
  return result ?? false;
}
