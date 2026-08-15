import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/animations/animation_helpers.dart';
import '../../../core/animations/animation_tokens.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../shared/components/cards/sa_card.dart';
import '../../../shared/components/charts/sa_bar_chart.dart';
import '../../../shared/components/charts/sa_donut_chart.dart';
import '../../../shared/components/charts/sa_heat_grid.dart';
import '../../../shared/components/charts/sa_sparkline.dart';
import '../../../shared/components/feedback/sa_battery_bar.dart';
import '../../../shared/components/feedback/sa_empty_state.dart';
import '../../../shared/components/feedback/sa_loading_shimmer.dart';
import '../../../shared/components/feedback/sa_progress_ring.dart';
import '../../../shared/components/feedback/sa_threat_chip.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/navigation/sa_bottom_nav_bar.dart';
import '../../../shared/components/overlays/sa_bottom_sheet.dart';
import '../../../shared/models/threat_level.dart';
import '../../../shared/utils/user_error.dart';
import '../data/dashboard_providers.dart';
import '../domain/models/dashboard_analytics.dart';

/// SRS Part 3, SCREEN 9 — the retrospective view.
///
/// Home answers "am I safe right now"; this screen answers "what has been
/// happening to me". Every figure comes from `GET /api/v1/dashboard/analytics`,
/// which aggregates the signed-in user's own incidents and refuses to
/// synthesise the ones it cannot compute — so the cards below have to render
/// three distinct states, not two: a value, "nothing recorded", and "this
/// cannot be known yet".
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
    final analyticsAsync = ref.watch(dashboardAnalyticsProvider);

    return Scaffold(
      body: Stack(
        children: [
          RefreshIndicator(
            color: AppColors.violet500,
            backgroundColor: context.saColors.surfaceElevated,
            onRefresh: () => ref.refresh(dashboardAnalyticsProvider.future),
            child: CustomScrollView(
              // Always scrollable so pull-to-refresh still works on the
              // empty and error states, which are shorter than the viewport.
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const _DashboardAppBar(),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenMarginPhone,
                    AppSpacing.space2,
                    AppSpacing.screenMarginPhone,
                    AppSpacing.space16 + AppSpacing.space8,
                  ),
                  sliver: analyticsAsync.when(
                    loading: () => const _DashboardSkeleton(),
                    // The message comes from the failure itself. Hardcoding
                    // "check your connection" here blamed the network for a
                    // 404 served by a backend older than the app, and sent a
                    // real debugging session after the wrong problem.
                    error: (error, _) => SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.space10),
                        child: Builder(
                          builder: (context) {
                            final failure = describeError(
                              error,
                              fallbackTitle: 'Couldn’t load your dashboard',
                            );
                            return SaEmptyState(
                              title: failure.title,
                              body: failure.message,
                              ctaLabel: 'Retry',
                              onCtaTap: () => ref.invalidate(dashboardAnalyticsProvider),
                            );
                          },
                        ),
                      ),
                    ),
                    data: (analytics) => analytics.isEmpty
                        ? const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.only(top: AppSpacing.space10),
                              child: SaEmptyState(
                                title: 'Nothing to report',
                                body:
                                    'No incidents have been recorded on your account. '
                                    'Your dashboard fills in as SafeHer watches over you.',
                              ),
                            ),
                          )
                        : _DashboardCards(analytics: analytics),
                  ),
                ),
              ],
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

class _DashboardAppBar extends StatelessWidget {
  const _DashboardAppBar();

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 128,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(
          left: AppSpacing.screenMarginPhone,
          bottom: AppSpacing.space4,
        ),
        title: Text(
          'Dashboard',
          style: AppTypography.headingM.copyWith(color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
    );
  }
}

/// Fade-in + 16dp rise, 50ms apart per card, per SRS SCREEN 9. Routed
/// through [AnimationHelpers] so that "disable animations" lands the cards
/// in place immediately instead of hiding them behind an opacity of 0.
class _StaggeredCard extends StatefulWidget {
  const _StaggeredCard({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_StaggeredCard> createState() => _StaggeredCardState();
}

class _StaggeredCardState extends State<_StaggeredCard> with SingleTickerProviderStateMixin {
  static const _delayPerCard = Duration(milliseconds: 50);

  /// The delay is baked into the controller's duration and skipped with an
  /// [Interval], rather than scheduled with a `Future.delayed`. A pending
  /// timer outlives a widget that scrolls out of a lazily-built sliver, and
  /// the test binding rightly treats that as a leak.
  late final Duration _delay = _delayPerCard * widget.index;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AnimationTokens.comfortable + _delay,
  );

  late final Animation<double> _entrance = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      _delay.inMicroseconds / (AnimationTokens.comfortable + _delay).inMicroseconds,
      1,
      curve: AnimationTokens.decelerateCurve,
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AnimationHelpers.forward(context, _controller);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, child) => Opacity(
        opacity: _entrance.value,
        child: Transform.translate(offset: Offset(0, 16 * (1 - _entrance.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

class _DashboardCards extends StatelessWidget {
  const _DashboardCards({required this.analytics});

  final DashboardAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _TotalIncidentsCard(analytics: analytics),
      _ThreatAnalyticsCard(days: analytics.threatDays),
      _LocationHeatmapCard(cells: analytics.heatCells),
      _SplitRow(
        left: _ConfidenceCard(segments: analytics.confidenceBreakdown),
        right: _RecentReportsCard(incidents: analytics.recentIncidents),
      ),
      _SplitRow(
        left: _DeviceHealthCard(
          devices: analytics.deviceHealth,
          historyAvailable: analytics.batteryHistoryAvailable,
        ),
        right: _SafetyScoreCard(score: analytics.safetyScore),
      ),
    ];

    return SliverList.separated(
      itemCount: cards.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.space4),
      itemBuilder: (context, index) => _StaggeredCard(index: index, child: cards[index]),
    );
  }
}

/// Two half-width cards side by side.
///
/// Deliberately not wrapped in [IntrinsicHeight], tempting as matched heights
/// are: several of these cards contain a [LayoutBuilder] (the charts size
/// themselves to their slot), and intrinsic measurement throws outright
/// against one. Each card takes its natural height instead.
class _SplitRow extends StatelessWidget {
  const _SplitRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: AppSpacing.space4),
        Expanded(child: right),
      ],
    );
  }
}

class _CardHeading extends StatelessWidget {
  const _CardHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.labelL.copyWith(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
      ),
    );
  }
}

// --------------------------------------------------------------- Card 1

class _TotalIncidentsCard extends StatelessWidget {
  const _TotalIncidentsCard({required this.analytics});

  final DashboardAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final trend = analytics.trendPct;
    final rising = (trend ?? 0) > 0;

    return SaCard(
      elevation: 2,
      padding: EdgeInsets.zero,
      semanticsLabel: 'Total incidents ${analytics.totalIncidents}',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.space5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl2),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.violet700, AppColors.violet500],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TOTAL INCIDENTS',
              style: AppTypography.labelM.copyWith(color: Colors.white.withValues(alpha: 0.75)),
            ),
            const SizedBox(height: AppSpacing.space2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${analytics.totalIncidents}',
                  style: AppTypography.displayL.copyWith(color: Colors.white),
                ),
                const SizedBox(width: AppSpacing.space3),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.space2),
                  child: trend == null
                      // No prior 30-day window to compare against. Saying so
                      // beats printing "0%", which would read as a measured
                      // result rather than an absent one.
                      ? Text(
                          'No prior period',
                          style: AppTypography.bodyS.copyWith(
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Transform.rotate(
                              angle: rising ? 0 : 3.14159,
                              child: SaIcon(
                                SaIconGlyph.chevronRight,
                                size: 16,
                                color: rising ? AppColors.coral400 : Colors.white,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${trend.abs().toStringAsFixed(1)}%',
                              style: AppTypography.labelL.copyWith(
                                color: rising ? AppColors.coral400 : Colors.white,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
            Text(
              'Last 30 days vs the 30 before',
              style: AppTypography.bodyS.copyWith(color: Colors.white.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: AppSpacing.space4),
            SaSparkline(values: analytics.incidentSparkline, color: Colors.white, height: 52),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- Card 2

class _ThreatAnalyticsCard extends StatelessWidget {
  const _ThreatAnalyticsCard({required this.days});

  final List<ThreatDay> days;

  void _showDay(BuildContext context, ThreatDay day) {
    showSaBottomSheet<void>(
      context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Text(
              _formatDate(day.date),
              style: AppTypography.headingS.copyWith(
                color: Theme.of(sheetContext).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              day.total == 0
                  ? 'No incidents recorded.'
                  : '${day.total} incident${day.total == 1 ? '' : 's'} recorded.',
              style: AppTypography.bodyM.copyWith(
                color: Theme.of(sheetContext).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            if (day.total > 0) ...[
              const SizedBox(height: AppSpacing.space4),
              for (final entry in day.counts.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.space2),
                  child: Row(
                    children: [
                      SaThreatChip(level: _levelForLabel(entry.key)),
                      const SizedBox(width: AppSpacing.space3),
                      Text(
                        '${entry.value} × ${entry.key}',
                        style: AppTypography.bodyM.copyWith(
                          color: Theme.of(sheetContext).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.space2),
              TextButton(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  sheetContext.go('/reports');
                },
                child: const Text('View all reports'),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SaCard(
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeading('THREAT ANALYTICS'),
          const SizedBox(height: AppSpacing.space1),
          Text(
            'Last 14 days',
            style: AppTypography.bodyS.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: AppSpacing.space4),
          SaBarChart(
            data: [
              for (final day in days)
                SaBarChartDatum(
                  label: '${day.date.day}',
                  value: day.total.toDouble(),
                  level: day.level,
                ),
            ],
            height: 180,
            onBarTap: (index) => _showDay(context, days[index]),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- Card 3

class _LocationHeatmapCard extends StatelessWidget {
  const _LocationHeatmapCard({required this.cells});

  final List<SaHeatCell> cells;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return SaCard(
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeading('WHERE INCIDENTS HAPPENED'),
          const SizedBox(height: AppSpacing.space1),
          Text(
            cells.isEmpty
                ? 'None of your incidents carried a location'
                : 'Grouped into ~1 km areas',
            style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: AppSpacing.space4),
          SaHeatGrid(cells: cells),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- Card 4

class _ConfidenceCard extends StatelessWidget {
  const _ConfidenceCard({required this.segments});

  final List<SaDonutSegment> segments;

  @override
  Widget build(BuildContext context) {
    return SaCard(
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeading('SEVERITY MIX'),
          const SizedBox(height: AppSpacing.space4),
          Center(child: SaDonutChart(segments: segments, size: 116, strokeWidth: 16)),
          const SizedBox(height: AppSpacing.space3),
          for (final segment in segments)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space1),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: segment.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: AppSpacing.space2),
                  Expanded(
                    child: Text(
                      segment.label,
                      style: AppTypography.bodyS.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${segment.value.toInt()}',
                    style: AppTypography.monoDataS.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- Card 5

class _RecentReportsCard extends StatelessWidget {
  const _RecentReportsCard({required this.incidents});

  final List<RecentIncident> incidents;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return SaCard(
      elevation: 2,
      onTap: () => context.go('/reports'),
      semanticsLabel: 'Recent reports, ${incidents.length} items',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeading('RECENT REPORTS'),
          const SizedBox(height: AppSpacing.space3),
          if (incidents.isEmpty)
            Text(
              'No reports yet',
              style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.5)),
            ),
          for (final incident in incidents)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    incident.title,
                    style: AppTypography.bodyM.copyWith(color: onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _relativeTime(incident.createdAt),
                    style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- Card 6

class _DeviceHealthCard extends StatelessWidget {
  const _DeviceHealthCard({required this.devices, required this.historyAvailable});

  final List<DeviceHealth> devices;

  /// False while the backend keeps only a current battery reading per
  /// device. Drawing a "trend" from one sample would be a lie, so the card
  /// shows live levels and labels them as such.
  final bool historyAvailable;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return SaCard(
      elevation: 2,
      onTap: () => context.go('/devices'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeading('DEVICE HEALTH'),
          const SizedBox(height: AppSpacing.space1),
          Text(
            historyAvailable ? 'Battery trend' : 'Current battery',
            style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: AppSpacing.space3),
          if (devices.isEmpty)
            Text(
              'No devices paired',
              style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.5)),
            ),
          for (final device in devices)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.deviceName,
                    style: AppTypography.bodyS.copyWith(color: onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.space1),
                  if (device.batteryLevel == null)
                    Text(
                      'Never reported',
                      style: AppTypography.bodyS.copyWith(
                        color: onSurface.withValues(alpha: 0.5),
                      ),
                    )
                  else
                    SaBatteryBar(percent: device.batteryLevel! / 100),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- Card 7

class _SafetyScoreCard extends StatelessWidget {
  const _SafetyScoreCard({required this.score});

  final SafetyScore score;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final streak = score.incidentFreeStreakDays;

    return SaCard(
      elevation: 2,
      semanticsLabel:
          'Weekly safety score ${score.score} out of 100, '
          '$streak incident-free day${streak == 1 ? '' : 's'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeading('SAFETY SCORE'),
          const SizedBox(height: AppSpacing.space1),
          Text(
            'Last ${score.windowDays} days',
            style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: AppSpacing.space4),
          Center(
            child: SaProgressRing(
              progress: score.progress,
              size: 108,
              label: '${score.score}',
              color: _scoreColor(score.score),
            ),
          ),
          const SizedBox(height: AppSpacing.space4),
          Row(
            children: [
              const SaIcon(SaIconGlyph.shield, size: 16, color: AppColors.success500),
              const SizedBox(width: AppSpacing.space2),
              Expanded(
                child: Text(
                  streak == 0
                      ? 'Incident today'
                      : '$streak incident-free day${streak == 1 ? '' : 's'}',
                  style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.7)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _scoreColor(int score) {
    if (score >= 80) return AppColors.success500;
    if (score >= 50) return AppColors.warning500;
    return AppColors.coral500;
  }
}

// ------------------------------------------------------------- Skeleton

/// Shimmer placeholders shaped like the real cards, so the layout doesn't
/// jump when data lands.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    const heights = [188.0, 268.0, 268.0, 240.0, 240.0];
    return SliverList.separated(
      itemCount: heights.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.space4),
      itemBuilder: (context, index) => SaLoadingShimmer(
        child: Container(
          height: heights[index],
          decoration: BoxDecoration(
            color: context.saColors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppRadius.xl2),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- helpers

ThreatLevel _levelForLabel(String label) => switch (label.toLowerCase()) {
  'critical' => ThreatLevel.danger,
  'high' => ThreatLevel.elevated,
  'medium' || 'unknown' => ThreatLevel.caution,
  _ => ThreatLevel.safe,
};

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime date) => '${date.day} ${_months[date.month - 1]} ${date.year}';

String _relativeTime(DateTime timestamp) {
  final delta = DateTime.now().difference(timestamp);
  if (delta.inMinutes < 1) return 'Just now';
  if (delta.inHours < 1) return '${delta.inMinutes}m ago';
  if (delta.inDays < 1) return '${delta.inHours}h ago';
  if (delta.inDays < 7) return '${delta.inDays}d ago';
  return _formatDate(timestamp);
}
