import 'package:flutter/material.dart';

import '../../../core/animations/animation_helpers.dart';
import '../../../core/theme/theme_extensions.dart';

/// Sweeping shimmer placeholder. Wrap a solid-color shape sized/clipped to
/// match the real content it stands in for (e.g. a rounded rect the same
/// size as the card that will replace it).
class SaLoadingShimmer extends StatefulWidget {
  const SaLoadingShimmer({required this.child, super.key});

  final Widget child;

  @override
  State<SaLoadingShimmer> createState() => _SaLoadingShimmerState();
}

class _SaLoadingShimmerState extends State<SaLoadingShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AnimationHelpers.repeat(context, _controller);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    final base = saColors.surfaceHighest;
    final highlight = saColors.surfaceElevated;

    return Semantics(
      label: 'Loading',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) {
              final sweep = _controller.value * 2 - 1; // -1..1
              return LinearGradient(
                colors: [base, highlight, base],
                stops: const [0.35, 0.5, 0.65],
                begin: Alignment(-1 + sweep * 2, 0),
                end: Alignment(1 + sweep * 2, 0),
              ).createShader(bounds);
            },
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
