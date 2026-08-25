import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/layout/sa_section_header.dart';
import '../../../shared/components/cards/sa_threat_gauge_card.dart';
import '../../../shared/components/feedback/sa_empty_state.dart';
import '../../../shared/components/feedback/sa_status_dot.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/navigation/sa_bottom_nav_bar.dart';
import '../../devices/data/device_providers.dart';
import '../../devices/domain/models/device_detail.dart';
import '../data/monitoring_providers.dart';
import '../domain/models/realtime_alert_event.dart';
import 'widgets/camera_feed_panel.dart';

/// Live Monitoring — driven entirely by the real
/// `/api/v1/ws/alerts/{user_id}` feed (see `monitoring_providers.dart`).
/// There is no continuous sensor stream to show: the backend only
/// broadcasts discrete `threat_alert`/`emergency_alert` events, so this
/// screen shows real connection state plus a real, event-sourced list —
/// never a fabricated waveform or motion chart.
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
    final monitoring = ref.watch(liveMonitoringControllerProvider);
    final devicesAsync = ref.watch(devicesProvider);
    final glassesOnline = devicesAsync.valueOrNull?.any((d) => d.type == DeviceType.glasses && d.isOnline) ?? false;
    final latestEvent = monitoring.events.isNotEmpty ? monitoring.events.first : null;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _MonitoringHeader(status: monitoring.status),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenMarginPhone,
                      AppSpacing.space2,
                      AppSpacing.screenMarginPhone,
                      AppSpacing.space16 + AppSpacing.space8,
                    ),
                    child: _MonitoringBody(
                      status: monitoring.status,
                      events: monitoring.events,
                      latestEvent: latestEvent,
                      glassesOnline: glassesOnline,
                      onRetry: () => ref.read(liveMonitoringControllerProvider.notifier).retry(),
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
  const _MonitoringHeader({required this.status});

  final MonitoringConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isLive = status == MonitoringConnectionStatus.connected;
    final label = switch (status) {
      MonitoringConnectionStatus.connected => 'LIVE',
      MonitoringConnectionStatus.connecting => 'CONNECTING',
      MonitoringConnectionStatus.disconnected => 'OFFLINE',
    };
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
            semanticsLabel: 'Monitoring $label',
          ),
          const SizedBox(width: AppSpacing.space2),
          Text(label, style: AppTypography.labelM.copyWith(color: onSurface.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}

class _MonitoringBody extends StatelessWidget {
  const _MonitoringBody({
    required this.status,
    required this.events,
    required this.latestEvent,
    required this.glassesOnline,
    required this.onRetry,
  });

  final MonitoringConnectionStatus status;
  final List<RealtimeAlertEvent> events;
  final RealtimeAlertEvent? latestEvent;
  final bool glassesOnline;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SaThreatGaugeCard(
          score: latestEvent?.gaugeScore,
          componentScores: const [],
          lastUpdated: latestEvent != null ? _formatRelative(latestEvent!.timestamp) : null,
          gaugeSize: 120,
        ),
        const SizedBox(height: AppSpacing.space4),
        SizedBox(height: 220, child: CameraFeedPanel(glassesConnected: glassesOnline)),
        const SizedBox(height: AppSpacing.space4),
        const SaSectionHeader(label: 'Recent Events'),
        const SizedBox(height: AppSpacing.space3),
        if (events.isEmpty)
          SaEmptyState(
            title: status == MonitoringConnectionStatus.disconnected
                ? 'No live device data available'
                : 'No live events yet',
            body: status == MonitoringConnectionStatus.disconnected
                ? 'Connect your Smart Glove or Smart Glasses to begin monitoring.'
                : "You're connected — real alerts will appear here as they happen.",
            ctaLabel: status == MonitoringConnectionStatus.disconnected ? 'Retry Connection' : null,
            onCtaTap: status == MonitoringConnectionStatus.disconnected ? onRetry : null,
          )
        else
          for (final event in events) ...[
            _EventTile(event: event),
            const SizedBox(height: AppSpacing.space3),
          ],
      ],
    );
  }

  static String _formatRelative(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final RealtimeAlertEvent event;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isEmergency = event.kind == RealtimeAlertKind.emergency;
    final accent = isEmergency ? AppColors.coral500 : AppColors.violet500;
    return Semantics(
      label:
          '${isEmergency ? "Emergency alert" : "Threat alert"}: ${event.summary}'
          '${event.threatLevel != null ? ", ${event.threatLevel} severity" : ""}',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.space4),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SaIcon(isEmergency ? SaIconGlyph.shield : SaIconGlyph.monitorPulse, size: 20, color: accent),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.summary, style: AppTypography.bodyL.copyWith(color: onSurface)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (event.threatLevel != null) event.threatLevel!.toUpperCase(),
                      _MonitoringBody._formatRelative(event.timestamp),
                    ].join(' · '),
                    style: AppTypography.labelM.copyWith(color: onSurface.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
