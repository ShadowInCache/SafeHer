import 'package:flutter/material.dart';

import '../../../core/animations/animation_helpers.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../models/threat_level.dart';
import '../feedback/sa_threat_chip.dart';

/// Incident list row with a colored left border matching [level].
class SaIncidentCard extends StatefulWidget {
  const SaIncidentCard({
    required this.date,
    required this.type,
    required this.level,
    required this.summarySnippet,
    super.key,
    this.onTap,
  });

  final String date;
  final String type;
  final ThreatLevel level;
  final String summarySnippet;
  final VoidCallback? onTap;

  @override
  State<SaIncidentCard> createState() => _SaIncidentCardState();
}

class _SaIncidentCardState extends State<SaIncidentCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final color = widget.level.color(context);
    final scale = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );

    return Semantics(
      label: '${widget.type}, ${widget.level.label}, ${widget.date}',
      button: widget.onTap != null,
      child: GestureDetector(
        onTapDown: (_) => AnimationHelpers.forward(context, _pressController),
        onTapCancel: () => AnimationHelpers.reverse(context, _pressController),
        onTapUp: (_) => AnimationHelpers.reverse(context, _pressController),
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: scale,
          builder: (context, child) => Transform.scale(scale: scale.value, child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
            decoration: BoxDecoration(
              color: saColors.surfaceElevated,
              borderRadius: AppRadius.lgRadius,
              border: Border(left: BorderSide(color: color, width: 4)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(widget.date, style: AppTypography.monoDataS.copyWith(color: onSurface.withValues(alpha: 0.6))),
                          const SizedBox(width: AppSpacing.space2),
                          Flexible(
                            child: Text(
                              widget.type,
                              style: AppTypography.headingS.copyWith(color: onSurface),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.space1),
                      Text(
                        widget.summarySnippet,
                        style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.7)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.space2),
                SaThreatChip(level: widget.level, compact: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
