import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/cards/sa_card.dart';
import '../../../../shared/components/charts/sa_waveform.dart';

const _emotionColors = {
  'calm': AppColors.success500,
  'neutral': AppColors.warning500,
  'stressed': AppColors.coral500,
};

class AudioWaveformPanel extends StatelessWidget {
  const AudioWaveformPanel({required this.waveform, required this.dbLevel, required this.emotion, super.key});

  final List<double> waveform;
  final double dbLevel;
  final String emotion;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final emotionColor = _emotionColors[emotion] ?? AppColors.neutral400;
    return SaCard(
      semanticsLabel: 'Audio waveform, $dbLevel decibels, emotion $emotion',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Audio', style: AppTypography.headingS.copyWith(color: onSurface)),
          const SizedBox(height: AppSpacing.space3),
          Expanded(child: SaWaveform(amplitudes: waveform)),
          const SizedBox(height: AppSpacing.space3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${dbLevel.round()} dB', style: AppTypography.monoDataS.copyWith(color: onSurface.withValues(alpha: 0.6))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: emotionColor.withValues(alpha: 0.15),
                  borderRadius: AppRadius.fullRadius,
                  border: Border.all(color: emotionColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: emotionColor, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(emotion.toUpperCase(), style: AppTypography.labelM.copyWith(color: emotionColor)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
