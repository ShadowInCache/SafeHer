import 'package:flutter/material.dart';

import '../../../core/animations/animation_helpers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/theme_extensions.dart';

enum SaIconButtonVariant { filled, ghost, tonal }

enum SaIconButtonSize { small, large }

/// Compact icon-only button. [SaIconButtonSize.small] is 40dp,
/// [SaIconButtonSize.large] is 48dp, matching the 40/48dp spec.
class SaIconButton extends StatefulWidget {
  const SaIconButton({
    required this.icon,
    required this.onPressed,
    required this.semanticsLabel,
    super.key,
    this.variant = SaIconButtonVariant.ghost,
    this.size = SaIconButtonSize.large,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String semanticsLabel;
  final SaIconButtonVariant variant;
  final SaIconButtonSize size;

  @override
  State<SaIconButton> createState() => _SaIconButtonState();
}

class _SaIconButtonState extends State<SaIconButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;

  bool get _disabled => widget.onPressed == null;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 150),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    final dimension = widget.size == SaIconButtonSize.small ? 40.0 : 48.0;
    final scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOut, reverseCurve: Curves.elasticOut),
    );

    final (background, foreground) = switch (widget.variant) {
      SaIconButtonVariant.filled => (AppColors.violet500, Colors.white),
      SaIconButtonVariant.tonal => (saColors.surfaceHighest, Theme.of(context).colorScheme.onSurface),
      SaIconButtonVariant.ghost => (Colors.transparent, Theme.of(context).colorScheme.onSurface),
    };

    return Semantics(
      label: widget.semanticsLabel,
      button: true,
      enabled: !_disabled,
      child: GestureDetector(
        onTapDown: _disabled ? null : (_) => AnimationHelpers.forward(context, _pressController),
        onTapCancel: _disabled ? null : () => AnimationHelpers.reverse(context, _pressController),
        onTapUp: _disabled ? null : (_) => AnimationHelpers.reverse(context, _pressController),
        onTap: widget.onPressed,
        child: AnimatedBuilder(
          animation: scale,
          builder: (context, child) => Transform.scale(scale: scale.value, child: child),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: _disabled ? 0.4 : 1.0,
            child: Container(
              width: dimension,
              height: dimension,
              decoration: BoxDecoration(color: background, borderRadius: AppRadius.fullRadius),
              alignment: Alignment.center,
              child: IconTheme(data: IconThemeData(color: foreground, size: 22), child: widget.icon),
            ),
          ),
        ),
      ),
    );
  }
}
