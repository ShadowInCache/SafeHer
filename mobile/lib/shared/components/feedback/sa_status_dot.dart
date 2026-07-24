import 'package:flutter/material.dart';

import '../../../core/animations/animation_helpers.dart';

/// 8dp status indicator. When [live] is true it pulses gently to signal an
/// actively-updating state (device online, monitoring active, ...).
class SaStatusDot extends StatefulWidget {
  const SaStatusDot({required this.color, super.key, this.live = false, this.size = 8, this.semanticsLabel});

  final Color color;
  final bool live;
  final double size;
  final String? semanticsLabel;

  @override
  State<SaStatusDot> createState() => _SaStatusDotState();
}

class _SaStatusDotState extends State<SaStatusDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    if (widget.live) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AnimationHelpers.repeat(context, _controller, reverse: true);
      });
    }
  }

  @override
  void didUpdateWidget(covariant SaStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.live && !oldWidget.live) {
      AnimationHelpers.repeat(context, _controller, reverse: true);
    } else if (!widget.live && oldWidget.live) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticsLabel,
      excludeSemantics: widget.semanticsLabel != null,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final opacity = widget.live ? 0.5 + (_controller.value * 0.5) : 1.0;
          return Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: opacity),
              boxShadow: widget.live
                  ? [BoxShadow(color: widget.color.withValues(alpha: 0.4), blurRadius: widget.size)]
                  : null,
            ),
          );
        },
      ),
    );
  }
}
