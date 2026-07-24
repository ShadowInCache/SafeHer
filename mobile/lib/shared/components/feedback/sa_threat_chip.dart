import 'package:flutter/material.dart';

import '../../../core/animations/animation_helpers.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_typography.dart';
import '../../models/threat_level.dart';

/// Pill chip communicating a [ThreatLevel]. Colour alone never carries the
/// meaning — the label text is always shown alongside it. Pulses gently
/// when [level] is [ThreatLevel.danger] to draw attention.
class SaThreatChip extends StatefulWidget {
  const SaThreatChip({required this.level, super.key, this.compact = false});

  final ThreatLevel level;
  final bool compact;

  @override
  State<SaThreatChip> createState() => _SaThreatChipState();
}

class _SaThreatChipState extends State<SaThreatChip> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    if (widget.level == ThreatLevel.danger) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AnimationHelpers.repeat(context, _pulseController, reverse: true);
      });
    }
  }

  @override
  void didUpdateWidget(covariant SaThreatChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isDanger = widget.level == ThreatLevel.danger;
    final wasDanger = oldWidget.level == ThreatLevel.danger;
    if (isDanger && !wasDanger) {
      AnimationHelpers.repeat(context, _pulseController, reverse: true);
    } else if (!isDanger && wasDanger) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.level.color(context);
    final glow = widget.level.glowColor(context);

    return Semantics(
      label: 'Threat level ${widget.level.label}',
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final pulse = widget.level == ThreatLevel.danger ? _pulseController.value : 0.0;
          return Container(
            padding: EdgeInsets.symmetric(horizontal: widget.compact ? 8 : 12, vertical: widget.compact ? 4 : 6),
            decoration: BoxDecoration(
              color: Color.lerp(glow, color.withValues(alpha: 0.35), pulse),
              borderRadius: AppRadius.fullRadius,
              border: Border.all(color: color, width: 1),
            ),
            child: child,
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(
              widget.level.label,
              style: AppTypography.labelM.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
