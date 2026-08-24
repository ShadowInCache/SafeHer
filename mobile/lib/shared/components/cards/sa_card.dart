import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/animations/animation_helpers.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/theme_extensions.dart';

/// Base card used throughout SafeHer. Specialized cards (SaDeviceCard,
/// SaAlertCard, ...) compose this rather than reimplementing the
/// fill/border/shadow treatment.
///
/// **This used to be a glass card** — a 16px [BackdropFilter] behind a
/// translucent white fill, on every surface in the app. Two things were wrong
/// with that. Visually, it gave a dark-mode toggle and an SOS contact exactly
/// the same weight, so nothing had hierarchy. Mechanically, the filter ran
/// whether or not it was wanted: [useBlur] `false` still built a
/// `BackdropFilter`, just with a zero-sigma blur, which costs a saveLayer and
/// a GPU pass to produce no effect at all.
///
/// The fills are opaque now, so a backdrop filter has nothing left to reveal —
/// it blurs pixels that are then painted over. [useBlur] therefore defaults to
/// false and, when false, no filter is built at all. The flag survives only so
/// a surface that genuinely wants to sample what is behind it can ask; when
/// nothing does, it should go.
class SaCard extends StatefulWidget {
  const SaCard({
    required this.child,
    super.key,
    this.onTap,
    this.elevation = 2,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius,
    this.useBlur = false,
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

    // [elevation] has been dead for as long as this was a glass card. The
    // ClipRRect below existed for the filter's benefit, but a clip applies to
    // everything its child paints — including the drop shadow, which falls
    // *outside* the rounded rect and was therefore clipped away every time. No
    // SaCard has ever actually painted one.
    //
    // Removing the clip switched them all on at once, which is not a change
    // this pass is entitled to make: the direction takes its hierarchy from
    // hairlines and space rather than depth, and turning on shadows nobody
    // asked for is the opposite of flattening. So the flat surface keeps them
    // off deliberately, and the blurred path keeps its old behaviour. Retiring
    // the parameter itself belongs with the elevation work.
    final Widget surface = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: widget.padding,
      decoration: BoxDecoration(
        color: saColors.glassFill,
        borderRadius: radius,
        border: Border.all(color: saColors.glassBorder, width: 1),
        boxShadow: widget.useBlur ? _shadowFor(widget.elevation, saColors) : const [],
      ),
      child: widget.child,
    );

    // The decoration rounds its own corners, so with no filter to contain
    // there is nothing left for a clip to do.
    Widget content = widget.useBlur
        ? ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: surface,
            ),
          )
        : surface;

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
