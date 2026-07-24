import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/animations/animation_helpers.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/theme_extensions.dart';

/// Base glassmorphic card used throughout SafeHer. Specialized cards
/// (SaDeviceCard, SaAlertCard, ...) compose this rather than reimplementing
/// the glass fill/border/shadow treatment.
///
/// Per the glassmorphism spec, no more than 3 [SaCard]s with [useBlur] true
/// should be visible on screen simultaneously — screens with long lists
/// should set `useBlur: false` on cards past the first few.
class SaCard extends StatefulWidget {
  const SaCard({
    required this.child,
    super.key,
    this.onTap,
    this.elevation = 2,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius,
    this.useBlur = true,
    this.semanticsLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final int elevation;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final bool useBlur;
  final String? semanticsLabel;

  @override
  State<SaCard> createState() => _SaCardState();
}

class _SaCardState extends State<SaCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  List<BoxShadow> _shadowFor(int level, dynamic saColors) {
    return switch (level) {
      <= 0 => const [],
      1 => saColors.shadowLevel1 as List<BoxShadow>,
      2 => saColors.shadowLevel2 as List<BoxShadow>,
      3 => saColors.shadowLevel3 as List<BoxShadow>,
      4 => saColors.shadowLevel4 as List<BoxShadow>,
      _ => saColors.shadowLevel5 as List<BoxShadow>,
    };
  }

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    final radius = widget.borderRadius ?? AppRadius.xl2Radius;
    final scale = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );

    Widget content = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: widget.useBlur
            ? ImageFilter.blur(sigmaX: 16, sigmaY: 16)
            : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: saColors.glassFill,
            borderRadius: radius,
            border: Border.all(color: saColors.glassBorder, width: 1),
            boxShadow: _shadowFor(widget.elevation, saColors),
          ),
          child: widget.child,
        ),
      ),
    );

    if (widget.onTap != null) {
      content = GestureDetector(
        onTapDown: (_) => AnimationHelpers.forward(context, _pressController),
        onTapCancel: () => AnimationHelpers.reverse(context, _pressController),
        onTapUp: (_) => AnimationHelpers.reverse(context, _pressController),
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: scale,
          builder: (context, child) => Transform.scale(scale: scale.value, child: child),
          child: content,
        ),
      );
    }

    return Semantics(
      label: widget.semanticsLabel,
      button: widget.onTap != null,
      container: true,
      child: content,
    );
  }
}
