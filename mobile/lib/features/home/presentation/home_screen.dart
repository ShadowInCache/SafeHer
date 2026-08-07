import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/connectivity/connectivity_notifier.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../shared/components/cards/sa_alert_card.dart';
import '../../../shared/components/cards/sa_device_card.dart';
import '../../../shared/components/cards/sa_threat_gauge_card.dart';
import '../../../shared/components/feedback/sa_empty_state.dart';
import '../../../shared/components/feedback/sa_loading_shimmer.dart';
import '../../../shared/components/navigation/sa_bottom_nav_bar.dart';
import '../../../shared/components/overlays/sa_toast.dart';
import '../../devices/data/device_providers.dart';
import '../../devices/domain/models/device_detail.dart';
import '../../profile/data/profile_providers.dart';
import '../../reports/data/reports_providers.dart';
import '../../reports/domain/models/report_summary.dart';
import '../data/home_providers.dart';
import '../domain/models/home_summary.dart';
import 'widgets/home_greeting_section.dart';
import 'widgets/home_live_preview_section.dart';
import 'widgets/home_quick_actions.dart';
import 'widgets/home_safety_score_card.dart';

/// Command Center — the authenticated app's landing screen. Composes the
/// threat status, devices, quick actions, live-monitoring preview, recent
/// alerts, and daily safety score around the shared floating nav bar.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scrollController = ScrollController();
  double _scrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (!mounted) return;
      setState(() => _scrollOffset = _scrollController.offset.clamp(0, double.infinity));
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _handleTabSelected(SaNavTab tab) {
    switch (tab) {
      case SaNavTab.home:
        return;
      case SaNavTab.monitor:
        context.go('/monitor');
      case SaNavTab.dashboard:
        context.go('/dashboard');
      case SaNavTab.profile:
        context.go('/profile');
    }
  }

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(homeSummaryProvider);
    final profileAsync = ref.watch(userProfileProvider);
    final devicesAsync = ref.watch(devicesProvider);
    final reportsAsync = ref.watch(reportsListProvider);

    final error = summaryAsync.error ?? profileAsync.error ?? devicesAsync.error ?? reportsAsync.error;
    final hasAllData =
        summaryAsync.hasValue && profileAsync.hasValue && devicesAsync.hasValue && reportsAsync.hasValue;

    void retry() {
      ref.invalidate(homeSummaryProvider);
      ref.invalidate(userProfileProvider);
      ref.invalidate(devicesProvider);
      ref.invalidate(reportsListProvider);
    }

    return Scaffold(
      body: Stack(
        children: [
          error != null
              ? _HomeError(onRetry: retry)
              : !hasAllData
              ? const _HomeLoading()
              : _HomeContent(
                  summary: summaryAsync.requireValue,
                  userName: profileAsync.requireValue.name.split(' ').first,
                  devices: devicesAsync.requireValue,
                  recentAlerts: reportsAsync.requireValue.take(3).toList(),
                  scrollController: _scrollController,
                  scrollOffset: _scrollOffset,
                ),
          _BlurAppBar(scrollOffset: _scrollOffset),
          const Positioned(top: 0, left: 0, right: 0, child: SafeArea(bottom: false, child: _OfflineBanner())),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SaBottomNavBar(
              currentTab: SaNavTab.home,
              onTabSelected: _handleTabSelected,
              onSosTap: () => context.go('/emergency'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slides in below the status bar whenever [connectivityNotifierProvider]
/// reports no network — mutations made while it's visible (e.g. adding an
/// emergency contact) are queued locally and replay automatically once
/// it disappears. Absent entirely while online or while connectivity
/// state hasn't resolved yet, so this never flashes on a normal launch.
class _OfflineBanner extends ConsumerWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(connectivityNotifierProvider).valueOrNull == false;
    return AnimatedSlide(
      key: const ValueKey('offline-banner-slide'),
      duration: const Duration(milliseconds: 200),
      offset: isOffline ? Offset.zero : const Offset(0, -1.2),
      curve: Curves.easeOut,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space2),
        color: AppColors.warning500,
        child: Text(
          "You're offline — changes will sync when you're back online.",
          style: AppTypography.labelM.copyWith(color: Colors.black),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _BlurAppBar extends StatelessWidget {
  const _BlurAppBar({required this.scrollOffset});

  final double scrollOffset;

  @override
  Widget build(BuildContext context) {
    final opacity = (scrollOffset / 100).clamp(0.0, 1.0);
    final saColors = context.saColors;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: opacity,
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                height: MediaQuery.of(context).padding.top + 56,
                color: saColors.surfaceElevated.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeContent extends ConsumerWidget {
  const _HomeContent({
    required this.summary,
    required this.userName,
    required this.devices,
    required this.recentAlerts,
    required this.scrollController,
    required this.scrollOffset,
  });

  final HomeSummary summary;
  final String userName;
  final List<DeviceDetail> devices;
  final List<ReportSummary> recentAlerts;
  final ScrollController scrollController;
  final double scrollOffset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return CustomScrollView(
      controller: scrollController,
      physics: const ClampingScrollPhysics(),
      slivers: [
        SliverPadding(padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top)),
        SliverToBoxAdapter(
          child: HomeGreetingSection(
            userName: userName,
            hasUnreadAlerts: summary.hasUnreadAlerts,
            onBellTap: () {},
            onSearchTap: () => context.go('/search'),
            parallaxOffset: scrollOffset,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          sliver: SliverToBoxAdapter(
            child: SaThreatGaugeCard(
              score: summary.threat.score,
              componentScores: [
                SaComponentScore(label: 'Motion', score: summary.threat.motionScore),
                SaComponentScore(label: 'Audio', score: summary.threat.audioScore),
                SaComponentScore(label: 'Vision', score: summary.threat.visionScore),
              ],
              lastUpdated: _formatRelative(summary.threat.lastUpdated),
            ),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space5)),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
              itemCount: devices.length,
              separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.space3),
              itemBuilder: (context, index) {
                final device = devices[index];
                return SaDeviceCard(
                  name: device.name,
                  batteryPercent: device.batteryPercent,
                  signalStrength: device.signalStrength,
                  isOnline: device.isOnline,
                  onTap: () => context.go('/devices/${device.id}'),
                );
              },
            ),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space5)),
        SliverToBoxAdapter(
          child: HomeQuickActionsGrid(
            onSos: () => context.go('/emergency'),
            onCallContact: () => context.go('/profile'),
            onShareLocation: () => showSaToast(context, message: 'Location shared with your emergency contacts.'),
            onRecordEvidence: () => showSaToast(context, message: 'Evidence recording started.'),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space5)),
        SliverToBoxAdapter(
          child: HomeLivePreviewSection(
            waveform: summary.waveformPreview,
            motionPreview: summary.motionPreview,
            onViewLiveFeed: () => context.go('/monitor'),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space5)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Recent Alerts', style: AppTypography.headingM.copyWith(color: onSurface)),
                const SizedBox(height: AppSpacing.space3),
                if (recentAlerts.isEmpty)
                  Text(
                    'No alerts yet. Nice and quiet out there.',
                    style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.6)),
                  ),
                for (final alert in recentAlerts) ...[
                  SaAlertCard(
                    title: alert.type,
                    timestamp: alert.date,
                    level: alert.level,
                    summary: alert.summarySnippet,
                    onTap: () => context.go('/reports/${alert.id}'),
                  ),
                  const SizedBox(height: AppSpacing.space3),
                ],
                Semantics(
                  button: true,
                  label: 'View all reports',
                  child: GestureDetector(
                    onTap: () => context.go('/reports'),
                    child: Text(
                      'View all reports →',
                      style: AppTypography.labelL.copyWith(color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space5)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          sliver: SliverToBoxAdapter(child: HomeSafetyScoreCard(summary: summary.safetyScore)),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space16 + AppSpacing.space10)),
      ],
    );
  }

  static String _formatRelative(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenMarginPhone),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SaLoadingShimmer(
              child: Container(height: 40, decoration: BoxDecoration(borderRadius: AppRadius.mdRadius, color: Colors.white)),
            ),
            const SizedBox(height: AppSpacing.space5),
            SaLoadingShimmer(
              child: Container(height: 180, decoration: BoxDecoration(borderRadius: AppRadius.xl2Radius, color: Colors.white)),
            ),
            const SizedBox(height: AppSpacing.space5),
            SaLoadingShimmer(
              child: Container(height: 150, decoration: BoxDecoration(borderRadius: AppRadius.xlRadius, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeError extends StatelessWidget {
  const _HomeError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SaEmptyState(
        title: "Couldn't load your dashboard",
        body: 'Check your connection and try again.',
        ctaLabel: 'Retry',
        onCtaTap: onRetry,
      ),
    );
  }
}
