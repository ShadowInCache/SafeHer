import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_extensions.dart';

/// Draggable glass sheet content with a handle bar. Use [showSaBottomSheet]
/// to present it modally (dismiss-on-swipe-down is provided by Flutter's
/// modal bottom sheet route).
class SaBottomSheet extends StatelessWidget {
  const SaBottomSheet({required this.child, super.key, this.padding = const EdgeInsets.all(AppSpacing.space5)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl2)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: saColors.surfaceElevated,
            border: Border(top: BorderSide(color: saColors.glassBorder)),
          ),
          padding: padding,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpacing.space4),
                    decoration: BoxDecoration(color: saColors.glassBorder, borderRadius: AppRadius.fullRadius),
                  ),
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Presents [builder]'s content as a modal [SaBottomSheet].
Future<T?> showSaBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SaBottomSheet(child: builder(ctx)),
  );
}
