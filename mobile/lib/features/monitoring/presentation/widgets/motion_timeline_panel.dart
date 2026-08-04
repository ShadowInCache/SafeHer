import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/cards/sa_card.dart';
import '../../../../shared/components/charts/sa_motion_chart.dart';
import '../../../../shared/components/overlays/sa_dialog.dart';

class MotionTimelinePanel extends StatelessWidget {
  const MotionTimelinePanel({required this.samples, required this.events, super.key});

  final List<MotionSample> samples;
  final List<MotionEventPin> events;

  void _showPinDetail(BuildContext context, MotionEventPin pin) {
    showSaDialog<void>(
      context,
      title: pin.label,
      message: 'Detected at ${pin.timestamp}',
      actions: [SaDialogAction(label: 'Close', onPressed: () => Navigator.of(context).pop())],
    );
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SaCard(
      semanticsLabel: 'Motion timeline, ${events.length} detected events',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Motion', style: AppTypography.headingS.copyWith(color: onSurface)),
          const SizedBox(height: AppSpacing.space3),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SaMotionChart(
                samples: samples,
                events: events,
                onPinTap: (pin) => _showPinDetail(context, pin),
                height: constraints.maxHeight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
