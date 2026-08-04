import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/cards/sa_analytics_card.dart';
import '../../../shared/components/cards/sa_stat_card.dart';
import '../../../shared/components/charts/sa_bar_chart.dart';
import '../../../shared/components/charts/sa_donut_chart.dart';
import '../../../shared/components/charts/sa_heat_grid.dart';
import '../../../shared/components/charts/sa_sparkline.dart';
import '../../../shared/components/feedback/sa_empty_state.dart';
import '../../../shared/components/feedback/sa_loading_shimmer.dart';
import '../../../shared/components/navigation/sa_bottom_nav_bar.dart';
import '../data/dashboard_providers.dart';
import '../domain/models/dashboard_summary.dart';

/// Analytics dashboard — headline stats, weekly threat trend, event
/// breakdown, safety score history, and an incident heat grid.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  void _handleTabSelected(BuildContext context, SaNavTab tab) {
    switch (tab) {
      case SaNavTab.home:
        context.go('/home');
      case SaNavTab.monitor:
        context.go('/monitor');
      case SaNavTab.dashboard:
        return;
      case SaNavTab.profile:
        context.go('/profile');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);

    return Scaffold(
      body: Stack(
        children: [
          summaryAsync.when(
            data: (summary) => _DashboardContent(summary: summary),
            loading: () => const _DashboardLoading(),
            error: (error, stackTrace) => SafeArea(
              child: SaEmptyState(
                title: "Couldn't load your dashboard",
                body: 'Check your connection and try again.',
                ctaLabel: 'Retry',
                onCtaTap: () => ref.invalidate(dashboardSummaryProvider),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SaBottomNavBar(
              currentTab: SaNavTab.dashboard,
              onTabSelected: (tab) => _handleTabSelected(context, tab),
              onSosTap: () => context.go('/emergency'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return CustomScrollView(
      physics: const ClampingScrollPhysics(),
      slivers: [
        SliverPadding(padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenMarginPhone,
            AppSpacing.space4,
            AppSpacing.screenMarginPhone,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: Text('Dashboard', style: AppTypography.headingL.copyWith(color: onSurface)),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space4)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppSpacing.space3,
              crossAxisSpacing: AppSpacing.space3,
              childAspectRatio: 1.15,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final stat = summary.stats[index];
                return SaStatCard(value: stat.value, label: stat.label, trend: stat.trend, icon: stat.icon);
              },
              childCount: summary.stats.length,
            ),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space5)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          sliver: SliverToBoxAdapter(
            child: SaAnalyticsCard(
              title: 'Weekly Threat Trend',
              chart: SaBarChart(data: summary.weeklyThreatTrend),
            ),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space4)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          sliver: SliverToBoxAdapter(
            child: SaAnalyticsCard(
              title: 'Event Breakdown',
              chart: _EventBreakdownChart(segments: summary.eventBreakdown),
            ),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space4)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          sliver: SliverToBoxAdapter(
            child: SaAnalyticsCard(
              title: 'Safety Score Trend',
              chart: SaSparkline(values: summary.safetyScoreTrend, height: 80),
            ),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space4)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          sliver: SliverToBoxAdapter(
            child: SaAnalyticsCard(
              title: 'Incident Heat Grid',
              chart: SaHeatGrid(grid: summary.locationHeatGrid),
            ),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space16 + AppSpacing.space10)),
      ],
    );
  }
}

class _EventBreakdownChart extends StatelessWidget {
  const _EventBreakdownChart({required this.segments});

  final List<SaDonutSegment> segments;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        SaDonutChart(segments: segments),
        const SizedBox(width: AppSpacing.space4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final segment in segments)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.space2),
                  child: Row(
                    children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: segment.color, shape: BoxShape.circle)),
                      const SizedBox(width: AppSpacing.space2),
                      Expanded(
                        child: Text(
                          segment.label,
                          style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.7)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        segment.value.toInt().toString(),
                        style: AppTypography.labelM.copyWith(color: onSurface),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenMarginPhone),
        physics: const ClampingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SaLoadingShimmer(
              child: Container(height: 32, decoration: BoxDecoration(borderRadius: AppRadius.mdRadius, color: Colors.white)),
            ),
            const SizedBox(height: AppSpacing.space4),
            SaLoadingShimmer(
              child: Container(height: 100, decoration: BoxDecoration(borderRadius: AppRadius.xl2Radius, color: Colors.white)),
            ),
            const SizedBox(height: AppSpacing.space4),
            SaLoadingShimmer(
              child: Container(height: 220, decoration: BoxDecoration(borderRadius: AppRadius.xl2Radius, color: Colors.white)),
            ),
            const SizedBox(height: AppSpacing.space4),
            SaLoadingShimmer(
              child: Container(height: 180, decoration: BoxDecoration(borderRadius: AppRadius.xl2Radius, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
