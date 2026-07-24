import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/cards/sa_card.dart';
import '../../../../shared/components/charts/sa_sparkline.dart';
import '../../../../shared/components/charts/sa_waveform.dart';

/// Mini audio waveform + motion sparkline preview with a link to the full
/// Live Monitoring screen. Hero-tagged "monitor_preview" so tapping through
/// morphs into the matching panel on that screen.
class HomeLivePreviewSection extends StatelessWidget {
  const HomeLivePreviewSection({
    required this.waveform,
    required this.motionPreview,
    required this.onViewLiveFeed,
    super.key,
  });

  final List<double> waveform;
  final List<double> motionPreview;
  final VoidCallback onViewLiveFeed;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
      child: Hero(
        tag: 'monitor_preview',
        child: SaCard(
          onTap: onViewLiveFeed,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Live Monitoring', style: AppTypography.headingS.copyWith(color: onSurface)),
              const SizedBox(height: AppSpacing.space3),
              SizedBox(height: 48, child: SaWaveform(amplitudes: waveform, height: 48)),
              const SizedBox(height: AppSpacing.space3),
              SizedBox(height: 48, child: SaSparkline(values: motionPreview, height: 48, color: AppColors.violet500)),
              const SizedBox(height: AppSpacing.space3),
              GestureDetector(
                onTap: onViewLiveFeed,
                child: Text(
                  'View Live Feed →',
                  style: AppTypography.labelL.copyWith(color: AppColors.violet500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
