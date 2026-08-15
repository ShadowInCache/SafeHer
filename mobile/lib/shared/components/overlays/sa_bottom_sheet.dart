import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_extensions.dart';

/// Draggable glass sheet content with a handle bar. Use [showSaBottomSheet]
/// to present it modally (dismiss-on-swipe-down is provided by Flutter's
/// modal bottom sheet route).
class SaBottomSheet extends StatelessWidget {
  const SaBottomSheet({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(AppSpacing.space5),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    // Constrained here rather than only at the showModalBottomSheet call
    // site: `isScrollControlled: true` hands the sheet unbounded height, so
    // a form taller than the screen lays out past the bottom of it and its
    // last control becomes untappable — no overflow stripe, no exception,
    // just a button nothing can reach. Capping the height is what lets the
    // Flexible/SingleChildScrollView below actually scroll.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      child: ClipRRect(
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
                      decoration: BoxDecoration(
                        color: saColors.glassBorder,
                        borderRadius: AppRadius.fullRadius,
                      ),
                    ),
                  ),
                  // Scrollable, not just tall: the sheet sizes to its content
                  // (mainAxisSize.min) but the content can exceed the screen
                  // once a keyboard is up, a form gains a field, or the system
                  // font scale is turned up. Without this the last control is
                  // simply unreachable — which is how an added email field
                  // silently broke the "Add Contact" button.
                  Flexible(child: SingleChildScrollView(child: child)),
                ],
              ),
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
    // `isScrollControlled: true` hands the sheet unbounded height, so a
    // form taller than the screen simply lays out past the bottom of it and
    // its last control becomes untappable — no overflow stripe, no error,
    // just a button nothing can reach. Capping the height is what lets the
    // Flexible/SingleChildScrollView inside SaBottomSheet do its job.
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
    builder: (ctx) => SaBottomSheet(child: builder(ctx)),
  );
}
