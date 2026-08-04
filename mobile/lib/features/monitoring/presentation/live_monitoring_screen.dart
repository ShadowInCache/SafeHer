import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/feedback/sa_empty_state.dart';
import '../../../shared/components/feedback/sa_loading_shimmer.dart';
import '../../../shared/components/feedback/sa_status_dot.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/navigation/sa_bottom_nav_bar.dart';
import '../data/monitoring_providers.dart';
import '../domain/models/monitoring_snapshot.dart';
import 'widgets/audio_waveform_panel.dart';
import 'widgets/camera_feed_panel.dart';
import 'widgets/motion_timeline_panel.dart';
import 'widgets/threat_gauge_panel.dart';

const _tabletBreakpoint = 600.0;

/// Live Monitoring — a full-screen, non-scrolling composition of the four
/// real-time panels (threat gauge, audio, motion, camera). 1 column on
/// phones with the gauge filling the top 40%; 2x2 grid on tablets.
class LiveMonitoringScreen extends ConsumerWidget {
  const LiveMonitoringScreen({super.key});

  void _handleTabSelected(BuildContext context, SaNavTab tab) {
    switch (tab) {
      case SaNavTab.home:
        context.go('/home');
      case SaNavTab.monitor:
        return;
      case SaNavTab.dashboard:
        context.go('/dashboard');
      case SaNavTab.profile:
        context.go('/profile');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(monitoringStreamProvider);

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _MonitoringHeader(isLive: snapshotAsync.hasValue),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenMarginPhone,
                      AppSpacing.space2,
                      AppSpacing.screenMarginPhone,
                      AppSpacing.space16 + AppSpacing.space8,
                    ),
                    child: snapshotAsync.when(
                      data: (snapshot) => _MonitoringPanels(snapshot: snapshot),
                      loading: () => const _MonitoringLoading(),
                      error: (error, stackTrace) => SaEmptyState(
                        title: "Couldn't start live monitoring",
                        body: 'Check your connection and try again.',
                        ctaLabel: 'Retry',
                        onCtaTap: () => ref.invalidate(monitoringStreamProvider),
                      ),
                    ),
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
              currentTab: SaNavTab.monitor,
              onTabSelected: (tab) => _handleTabSelected(context, tab),
              onSosTap: () => context.go('/emergency'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonitoringHeader extends StatelessWidget {
  const _MonitoringHeader({required this.isLive});

  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.space2, AppSpacing.space2, AppSpacing.screenMarginPhone, 0),
      child: Row(
        children: [
          IconButton(
            icon: const SaIcon(SaIconGlyph.chevronLeft),
            onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
            tooltip: 'Back',
          ),
          Expanded(
            child: Text(
              'Live Monitoring',
              style: AppTypography.headingM.copyWith(color: onSurface),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.space2),
          SaStatusDot(
            color: isLive ? AppColors.success500 : AppColors.neutral400,
            live: isLive,
            semanticsLabel: isLive ? 'Monitoring live' : 'Monitoring connecting',
          ),
          const SizedBox(width: AppSpacing.space2),
          Text(
            isLive ? 'LIVE' : 'CONNECTING',
            style: AppTypography.labelM.copyWith(color: onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

class _MonitoringPanels extends StatelessWidget {
  const _MonitoringPanels({required this.snapshot});

  final MonitoringSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth >= _tabletBreakpoint;
        final gauge = ThreatGaugePanel(score: snapshot.threatScore);
        final audio = AudioWaveformPanel(
          waveform: snapshot.waveform,
          dbLevel: snapshot.dbLevel,
          emotion: snapshot.detectedEmotion,
        );
        final motion = MotionTimelinePanel(samples: snapshot.motionWindow, events: snapshot.eventPins);
        final camera = CameraFeedPanel(glassesConnected: snapshot.glassesConnected);

        if (isTablet) {
          return Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: gauge),
                    const SizedBox(width: AppSpacing.space4),
                    Expanded(child: audio),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.space4),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: motion),
                    const SizedBox(width: AppSpacing.space4),
                    Expanded(child: camera),
                  ],
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            Expanded(flex: 4, child: gauge),
            const SizedBox(height: AppSpacing.space3),
            Expanded(flex: 2, child: audio),
            const SizedBox(height: AppSpacing.space3),
            Expanded(flex: 2, child: motion),
            const SizedBox(height: AppSpacing.space3),
            Expanded(flex: 2, child: camera),
          ],
        );
      },
    );
  }
}

class _MonitoringLoading extends StatelessWidget {
  const _MonitoringLoading();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 4,
          child: SaLoadingShimmer(
            child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.xl2Radius)),
          ),
        ),
        const SizedBox(height: AppSpacing.space3),
        for (var i = 0; i < 3; i++) ...[
          Expanded(
            flex: 2,
            child: SaLoadingShimmer(
              child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.xl2Radius)),
            ),
          ),
          if (i < 2) const SizedBox(height: AppSpacing.space3),
        ],
      ],
    );
  }
}
