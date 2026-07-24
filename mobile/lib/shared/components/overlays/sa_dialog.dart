import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_extensions.dart';
import '../buttons/sa_button.dart';

class SaDialogAction {
  const SaDialogAction({required this.label, required this.onPressed, this.isDestructive = false});

  final String label;
  final VoidCallback onPressed;
  final bool isDestructive;
}

/// Rounded glass modal with a title, optional message, and an action row.
/// Use [showSaDialog] to present it with a blurred barrier.
class SaDialog extends StatelessWidget {
  const SaDialog({required this.title, super.key, this.message, this.actions = const []});

  final String title;
  final String? message;
  final List<SaDialogAction> actions;

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
          Text(title, style: AppTypography.headingL.copyWith(color: onSurface)),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.space2),
            Text(message!, style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.7))),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.space5),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.space2),
                  SaButton(
                    label: actions[i].label,
                    size: SaButtonSize.sm,
                    variant: actions[i].isDestructive ? SaButtonVariant.danger : SaButtonVariant.ghost,
                    onPressed: actions[i].onPressed,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Presents an [SaDialog] with a blurred barrier.
Future<T?> showSaDialog<T>(
  BuildContext context, {
  required String title,
  String? message,
  List<SaDialogAction> actions = const [],
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return Material(
        type: MaterialType.transparency,
        child: Center(child: SaDialog(title: title, message: message, actions: actions)),
      );
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      return BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 8 * animation.value,
          sigmaY: 8 * animation.value,
        ),
        child: FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: Tween(begin: 0.95, end: 1.0).animate(animation), child: child),
        ),
      );
    },
  );
}
