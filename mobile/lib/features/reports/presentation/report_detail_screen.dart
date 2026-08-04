import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../shared/components/cards/sa_card.dart';
import '../../../shared/components/charts/sa_motion_chart.dart';
import '../../../shared/components/charts/sa_waveform.dart';
import '../../../shared/components/feedback/sa_empty_state.dart';
import '../../../shared/components/feedback/sa_loading_shimmer.dart';
import '../../../shared/components/feedback/sa_threat_chip.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../data/reports_providers.dart';
import '../domain/models/report_detail.dart';

/// Full detail for a single past incident report: what was detected, when,
/// where, and a frozen snapshot of the sensor data around the event.
class ReportDetailScreen extends ConsumerWidget {
  const ReportDetailScreen({required this.reportId, super.key});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(reportDetailProvider(reportId));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.space2, AppSpacing.space2, AppSpacing.screenMarginPhone, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const SaIcon(SaIconGlyph.chevronLeft),
                    onPressed: () => context.canPop() ? context.pop() : context.go('/reports'),
                    tooltip: 'Back',
                  ),
                  Text('Report Detail', style: AppTypography.headingM.copyWith(color: Theme.of(context).colorScheme.onSurface)),
                ],
              ),
            ),
            Expanded(
              child: detailAsync.when(
                data: (detail) => _ReportDetailContent(detail: detail),
                loading: () => const _ReportDetailLoading(),
                error: (error, stackTrace) => SaEmptyState(
                  title: "Couldn't load this report",
                  body: 'Check your connection and try again.',
                  ctaLabel: 'Retry',
                  onCtaTap: () => ref.invalidate(reportDetailProvider(reportId)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportDetailContent extends StatelessWidget {
  const _ReportDetailContent({required this.detail});

  final ReportDetail detail;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenMarginPhone,
        AppSpacing.space2,
        AppSpacing.screenMarginPhone,
        AppSpacing.space8,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(detail.type, style: AppTypography.headingL.copyWith(color: onSurface)),
            ),
            const SizedBox(width: AppSpacing.space2),
            SaThreatChip(level: detail.level),
          ],
        ),
        const SizedBox(height: AppSpacing.space1),
        Text(
          '${detail.date} · ${detail.time}',
          style: AppTypography.monoDataS.copyWith(color: onSurface.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: AppSpacing.space5),
        SaCard(
          semanticsLabel: 'Summary',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Summary', style: AppTypography.headingS.copyWith(color: onSurface)),
              const SizedBox(height: AppSpacing.space2),
              Text(detail.fullSummary, style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.8))),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        _LocationCard(label: detail.locationLabel),
        const SizedBox(height: AppSpacing.space4),
        SaCard(
          semanticsLabel: 'Audio snapshot',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Audio', style: AppTypography.headingS.copyWith(color: onSurface)),
              const SizedBox(height: AppSpacing.space3),
              SaWaveform(amplitudes: detail.waveform),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        SaCard(
          semanticsLabel: 'Motion snapshot',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Motion', style: AppTypography.headingS.copyWith(color: onSurface)),
              const SizedBox(height: AppSpacing.space3),
              SaMotionChart(samples: detail.motionSamples, events: detail.motionEvents, height: 160),
            ],
          ),
        ),
      ],
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final saColors = context.saColors;
    return SaCard(
      semanticsLabel: 'Location, $label',
      child: Row(
        children: [
          SaIcon(SaIconGlyph.mapPin, size: 28, color: saColors.threatCaution),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Location', style: AppTypography.headingS.copyWith(color: onSurface)),
                const SizedBox(height: AppSpacing.space1),
                Text(label, style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportDetailLoading extends StatelessWidget {
  const _ReportDetailLoading();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenMarginPhone),
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SaLoadingShimmer(
            child: Container(height: 32, decoration: BoxDecoration(borderRadius: AppRadius.mdRadius, color: Colors.white)),
          ),
          const SizedBox(height: AppSpacing.space5),
          for (var i = 0; i < 4; i++) ...[
            SaLoadingShimmer(
              child: Container(height: 100, decoration: BoxDecoration(borderRadius: AppRadius.xl2Radius, color: Colors.white)),
            ),
            const SizedBox(height: AppSpacing.space4),
          ],
        ],
      ),
    );
  }
}
