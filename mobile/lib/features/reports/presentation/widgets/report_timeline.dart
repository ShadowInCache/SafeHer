import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../shared/components/icons/sa_icon.dart';
import '../../domain/models/timeline_event.dart';

SaIconGlyph _glyphFor(TimelineEventType type) => switch (type) {
  TimelineEventType.sensorEvent => SaIconGlyph.monitorPulse,
  TimelineEventType.aiDetection => SaIconGlyph.shield,
  TimelineEventType.alertTrigger => SaIconGlyph.bell,
  TimelineEventType.evidenceCaptured => SaIconGlyph.camera,
  TimelineEventType.contactNotified => SaIconGlyph.check,
};

/// Vertical event timeline — one icon-coded node per [TimelineEvent], newest
/// last (chronological top-to-bottom). Each node fades + slides in with a
/// stagger on first build.
class ReportTimeline extends StatelessWidget {
  const ReportTimeline({required this.events, super.key});

  final List<TimelineEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (var i = 0; i < events.length; i++)
          _TimelineNode(event: events[i], isLast: i == events.length - 1, index: i),
      ],
    );
  }
}

class _TimelineNode extends StatelessWidget {
  const _TimelineNode({required this.event, required this.isLast, required this.index});

  final TimelineEvent event;
  final bool isLast;
  final int index;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final saColors = context.saColors;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, value, child) =>
          Opacity(opacity: value, child: Transform.translate(offset: Offset((1 - value) * -16, 0), child: child)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: saColors.glassFill),
                  child: Center(child: SaIcon(_glyphFor(event.type), size: 16, color: onSurface)),
                ),
                if (!isLast) Expanded(child: Container(width: 1.5, color: onSurface.withValues(alpha: 0.12))),
              ],
            ),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.space5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(event.title, style: AppTypography.headingS.copyWith(color: onSurface)),
                        ),
                        Text(
                          event.timestamp,
                          style: AppTypography.monoDataS.copyWith(color: onSurface.withValues(alpha: 0.5)),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.space1),
                    Text(
                      event.description,
                      style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.7)),
                    ),
                    if (event.confidence != null) ...[
                      const SizedBox(height: AppSpacing.space2),
                      _ConfidenceBar(confidence: event.confidence!),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfidenceBar extends StatelessWidget {
  const _ConfidenceBar({required this.confidence});

  final double confidence;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: '${(confidence * 100).round()}% confidence',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: confidence,
              minHeight: 4,
              backgroundColor: onSurface.withValues(alpha: 0.1),
            ),
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(
            '${(confidence * 100).round()}% confidence',
            style: AppTypography.labelM.copyWith(color: onSurface.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }
}
