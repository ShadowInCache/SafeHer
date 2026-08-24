import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/connectivity/connectivity_notifier.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../shared/components/buttons/sa_button.dart';
import '../../../shared/components/cards/sa_alert_card.dart';
import '../../../shared/components/cards/sa_analytics_card.dart';
import '../../../shared/components/charts/sa_bar_chart.dart';
import '../../../shared/components/charts/sa_donut_chart.dart';
import '../../../shared/components/feedback/sa_empty_state.dart';
import '../../../shared/components/feedback/sa_loading_shimmer.dart';
import '../../../shared/components/feedback/sa_status_dot.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/navigation/sa_bottom_nav_bar.dart';
import '../../../shared/components/overlays/sa_toast.dart';
import '../../dashboard/data/dashboard_providers.dart';
import '../../dashboard/domain/models/dashboard_summary.dart';
import '../../devices/data/device_providers.dart';
import '../../devices/domain/models/device_detail.dart';
import '../../monitoring/data/monitoring_providers.dart';
import '../../monitoring/domain/models/realtime_alert_event.dart';
import '../../profile/data/profile_providers.dart';
import '../../reports/data/reports_providers.dart';
import '../../reports/domain/models/report_summary.dart';
import '../data/home_providers.dart';
import '../domain/models/home_summary.dart';
import 'widgets/home_greeting_section.dart';
import '../../../core/voice/voice_command.dart';
import '../../safety/presentation/safety_toolkit_screen.dart';
import 'widgets/home_quick_actions.dart';

/// Dashboard — SafeHer's single command-center screen: real safety status,
/// real device status, a real live-monitoring summary, quick actions, this
/// week's real trend, and recent alerts. There is no separate analytics-only
/// "Dashboard" screen anymore — it duplicated this one, so its real chart
/// data (weekly trend, event breakdown) now lives in the "This Week"
/// section below instead.
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
    final dashboardAsync = ref.watch(dashboardSummaryProvider);
    final monitoring = ref.watch(liveMonitoringControllerProvider);

    final error =
        summaryAsync.error ?? profileAsync.error ?? devicesAsync.error ?? reportsAsync.error ?? dashboardAsync.error;
    final hasAllData =
        summaryAsync.hasValue &&
        profileAsync.hasValue &&
        devicesAsync.hasValue &&
        reportsAsync.hasValue &&
        dashboardAsync.hasValue;

    void retry() {
      ref.invalidate(homeSummaryProvider);
      ref.invalidate(userProfileProvider);
      ref.invalidate(devicesProvider);
      ref.invalidate(reportsListProvider);
      ref.invalidate(dashboardSummaryProvider);
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
                  weeklySummary: dashboardAsync.requireValue,
                  monitoring: monitoring,
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
        // The deep end of the caution ramp, not the mid one. `warning500` is
        // tuned to be legible *as foreground* on either ground, which makes it
        // too dark to carry black text as a fill -- it lands at 4.5:1, right on
        // the line. This pairing is 8.8:1.
        color: AppColors.warning900,
        child: Text(
          "You're offline — changes will sync when you're back online.",
          style: AppTypography.labelM.copyWith(color: AppColors.neutral50),
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
          // The ground itself, opaque, rather than a translucent blur. This
          // header exists to hide content scrolling under the status bar, and
          // painting it in the page's own ground makes that read as the page
          // ending — which a frosted panel never quite did.
          child: Container(
            height: MediaQuery.of(context).padding.top + 56,
            color: saColors.surfaceBase,
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
    required this.weeklySummary,
    required this.monitoring,
    required this.scrollController,
    required this.scrollOffset,
  });

  final HomeSummary summary;
  final String userName;
  final List<DeviceDetail> devices;
  final List<ReportSummary> recentAlerts;
  final DashboardSummary weeklySummary;
  final LiveMonitoringState monitoring;
  final ScrollController scrollController;
  final double scrollOffset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final latestEvent = monitoring.events.isNotEmpty ? monitoring.events.first : null;

    return CustomScrollView(
      controller: scrollController,
      physics: const ClampingScrollPhysics(),
      slivers: [
        SliverPadding(padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top)),
        SliverToBoxAdapter(
          child: HomeGreetingSection(
            userName: userName,
            monitoringStatus: monitoring.status,
            onBellTap: () => showSaToast(context, message: "You're all caught up."),
            onSearchTap: () => context.go('/search'),
            parallaxOffset: scrollOffset,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          sliver: SliverToBoxAdapter(
            child: _SafetyStatusCard(
              hasDevices: devices.isNotEmpty,
              monitoringStatus: monitoring.status,
              latestEvent: latestEvent,
              threat: summary.threat,
              onConnectDevice: () => context.go('/devices'),
            ),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space5)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          sliver: SliverToBoxAdapter(
            child: _DeviceStatusSection(
              devices: devices,
              onDeviceTap: (device) => context.go('/devices/${device.id}'),
              onManageDevices: () => context.go('/devices'),
            ),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space5)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          sliver: SliverToBoxAdapter(
            child: _LiveMonitoringSummaryCard(monitoring: monitoring, onTap: () => context.go('/monitor')),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space5)),
        SliverToBoxAdapter(
          child: HomeQuickActionsGrid(
            onSos: () => context.go('/emergency'),
            // These two genuinely dial and genuinely compose a message with a
            // real GPS fix — they previously only showed a toast claiming the
            // action had happened.
            onCallContact: () => SafetyToolkitScreen.handleVoiceCommand(
              context,
              ref,
              VoiceCommand.callPrimaryContact,
            ),
            onShareLocation: () => SafetyToolkitScreen.handleVoiceCommand(
              context,
              ref,
              VoiceCommand.shareLocation,
            ),
            onFindHelp: () => context.go('/safety/nearby'),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space5)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(label: 'This Week'),
                const SizedBox(height: AppSpacing.space3),
                SaAnalyticsCard(title: 'Threat Trend', chart: SaBarChart(data: weeklySummary.weeklyThreatTrend)),
                if (weeklySummary.eventBreakdown.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.space4),
                  SaAnalyticsCard(
                    title: 'Event Breakdown',
                    chart: _EventBreakdownChart(segments: weeklySummary.eventBreakdown),
                  ),
                ],
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space5)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(
                  label: 'Recent Alerts',
                  actionLabel: 'All reports',
                  onAction: () => context.go('/reports'),
                ),
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
                    useBlur: false,
                  ),
                  const SizedBox(height: AppSpacing.space3),
                ],
                // The trailing "View all reports ->" link used to live here.
                // The section header now carries that action, and two controls
                // four rows apart going to the same route is a choice the
                // reader has to think about for no gain.
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: const SizedBox(height: AppSpacing.space16 + AppSpacing.space10)),
      ],
    );
  }
}

/// A rule, a mono label, and an optional action.
///
/// These were 18px semibold headings, which put "Devices" and "This Week" at
/// nearly the same weight as the safety status directly above them -- three
/// things competing to be the first thing read. Demoting the furniture is
/// what lets the status win without having to shout.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.actionLabel, this.onAction, this.trailing});

  final String label;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Right-hand slot for something that is not a link -- a live status, a
  /// count. Ignored when [actionLabel] is supplied; a section head has room
  /// for one thing on the right, and a tappable one wins.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: saColors.line),
        const SizedBox(height: AppSpacing.space3),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              label.toUpperCase(),
              // Uppercased for the eyebrow's look only. TalkBack and VoiceOver
              // spell an all-caps string letter by letter -- "T. H. I. S." --
              // so the accessible string stays as written.
              semanticsLabel: label,
              style: AppTypography.eyebrow.copyWith(color: saColors.inkMuted),
            ),
            if (actionLabel != null && onAction != null)
              Semantics(
                button: true,
                label: actionLabel,
                child: GestureDetector(
                  onTap: onAction,
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    actionLabel!,
                    style: AppTypography.labelM.copyWith(color: saColors.interactive),
                  ),
                ),
              )
            else if (trailing != null)
              trailing!,
          ],
        ),
      ],
    );
  }
}

enum _SafetyLevel { noDevice, safe, starting, elevated }

/// The hero card — leads with a plain-language safety status (per the
/// product spec's exact wording), never a bare percentage. A real gauge
/// still exists on the Live Monitoring screen for when someone wants the
/// underlying number.
class _SafetyStatusCard extends StatelessWidget {
  const _SafetyStatusCard({
    required this.hasDevices,
    required this.monitoringStatus,
    required this.latestEvent,
    required this.threat,
    required this.onConnectDevice,
  });

  final bool hasDevices;
  final MonitoringConnectionStatus monitoringStatus;
  final RealtimeAlertEvent? latestEvent;
  final ThreatSnapshot? threat;
  final VoidCallback onConnectDevice;

  _SafetyLevel get _level {
    if (!hasDevices) return _SafetyLevel.noDevice;
    final level = latestEvent?.threatLevel?.toLowerCase();
    if (level == 'high' || level == 'critical') return _SafetyLevel.elevated;
    if (monitoringStatus != MonitoringConnectionStatus.connected) return _SafetyLevel.starting;
    return _SafetyLevel.safe;
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final level = _level;

    final (glyph, tint, title, body) = switch (level) {
      _SafetyLevel.noDevice => (
        SaIconGlyph.bluetoothOff,
        AppColors.violet500,
        'No Wearable Connected',
        'Connect your Smart Glove or Smart Glasses to begin live monitoring.',
      ),
      _SafetyLevel.safe => (
        SaIconGlyph.shield,
        AppColors.success500,
        "You're Safe",
        'All connected devices are operating normally.',
      ),
      _SafetyLevel.starting => (
        SaIconGlyph.shield,
        AppColors.warning500,
        'Monitoring Starting',
        'Connecting to live monitoring…',
      ),
      _SafetyLevel.elevated => (
        SaIconGlyph.shield,
        AppColors.coral500,
        '${latestEvent?.threatLevel?.toUpperCase() ?? 'ELEVATED'} ALERT',
        latestEvent?.summary ?? 'A threat event was detected.',
      ),
    };

    return Semantics(
      label: '$title. $body',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.space5),
        decoration: BoxDecoration(
          borderRadius: AppRadius.xl2Radius,
          color: tint.withValues(alpha: 0.10),
          border: Border.all(color: tint.withValues(alpha: 0.38)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(shape: BoxShape.circle, color: tint.withValues(alpha: 0.18)),
              alignment: Alignment.center,
              child: SaIcon(glyph, size: 26, color: tint),
            ),
            const SizedBox(width: AppSpacing.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.headingM.copyWith(color: onSurface)),
                  const SizedBox(height: AppSpacing.space1),
                  Text(body, style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.75))),
                  if (level == _SafetyLevel.noDevice) ...[
                    const SizedBox(height: AppSpacing.space4),
                    SaButton(label: 'Connect Device', size: SaButtonSize.sm, onPressed: onConnectDevice),
                  ] else if (threat != null) ...[
                    const SizedBox(height: AppSpacing.space3),
                    Text(
                      'Threat score ${(threat!.score * 100).round()}% · updated ${_formatRelative(threat!.lastUpdated)}',
                      style: AppTypography.monoDataS.copyWith(color: onSurface.withValues(alpha: 0.5)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatRelative(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

SaIconGlyph _glyphForDeviceType(DeviceType type) => switch (type) {
  DeviceType.glove => SaIconGlyph.glove,
  DeviceType.glasses => SaIconGlyph.glasses,
  DeviceType.ring => SaIconGlyph.ring,
  DeviceType.pendant => SaIconGlyph.pendant,
};

class _DeviceStatusSection extends StatelessWidget {
  const _DeviceStatusSection({required this.devices, required this.onDeviceTap, required this.onManageDevices});

  final List<DeviceDetail> devices;
  final ValueChanged<DeviceDetail> onDeviceTap;
  final VoidCallback onManageDevices;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: 'Devices',
          actionLabel: 'Manage',
          onAction: onManageDevices,
        ),
        const SizedBox(height: AppSpacing.space3),
        if (devices.isEmpty)
          Semantics(
            button: true,
            label: 'No wearable connected. Tap to connect a device.',
            child: GestureDetector(
              onTap: onManageDevices,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
                child: Row(
                  children: [
                    SaIcon(SaIconGlyph.bluetoothOff, size: 22, color: onSurface.withValues(alpha: 0.4)),
                    const SizedBox(width: AppSpacing.space3),
                    Expanded(
                      child: Text(
                        'No wearable connected — tap to pair a Smart Glove or Smart Glasses.',
                        style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.6)),
                      ),
                    ),
                    SaIcon(SaIconGlyph.chevronRight, size: 18, color: onSurface.withValues(alpha: 0.4)),
                  ],
                ),
              ),
            ),
          )
        else
          // A register, not a stack of cards. Each device was its own filled,
          // bordered, rounded surface, which gave a paired smart ring exactly
          // the same visual weight as the safety status above it. The section
          // rule and the eyebrow already say where this list starts and ends,
          // so the rows only need separating from each other.
          for (final (i, device) in devices.indexed) ...[
            if (i > 0) Container(height: 1, color: context.saColors.line),
            _DeviceStatusRow(device: device, onTap: () => onDeviceTap(device)),
          ],
      ],
    );
  }
}

class _DeviceStatusRow extends StatelessWidget {
  const _DeviceStatusRow({required this.device, required this.onTap});

  final DeviceDetail device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final statusColor = device.isOnline ? AppColors.success500 : AppColors.neutral400;
    final syncedLabel = device.lastSeen != null ? 'Synced ${_formatRelative(device.lastSeen!)}' : 'Never synced';

    return Semantics(
      button: true,
      label:
          '${device.name}, ${device.isOnline ? "online" : "offline"}, $syncedLabel'
          '${device.isOnline ? ", battery ${(device.batteryPercent * 100).round()} percent" : ""}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.violet500.withValues(alpha: 0.15)),
                alignment: Alignment.center,
                child: SaIcon(_glyphForDeviceType(device.type), size: 20, color: AppColors.violet500),
              ),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.name, style: AppTypography.headingS.copyWith(color: onSurface)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        SaStatusDot(color: statusColor, live: device.isOnline),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${device.isOnline ? "Online" : "Offline"} · $syncedLabel',
                            style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.6)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (device.isOnline)
                Text(
                  '${(device.batteryPercent * 100).round()}%',
                  style: AppTypography.monoDataS.copyWith(color: onSurface.withValues(alpha: 0.7)),
                ),
              const SizedBox(width: AppSpacing.space2),
              SaIcon(SaIconGlyph.chevronRight, size: 16, color: onSurface.withValues(alpha: 0.35)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveMonitoringSummaryCard extends StatelessWidget {
  const _LiveMonitoringSummaryCard({required this.monitoring, required this.onTap});

  final LiveMonitoringState monitoring;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final latest = monitoring.events.isNotEmpty ? monitoring.events.first : null;
    final (statusLabel, statusColor) = switch (monitoring.status) {
      MonitoringConnectionStatus.connected => ('Live', AppColors.success500),
      MonitoringConnectionStatus.connecting => ('Connecting', AppColors.warning500),
      MonitoringConnectionStatus.disconnected => ('Offline', AppColors.neutral400),
    };

    // A section, not a floating card. This sat between the device register
    // and the quick-action grid as the one block with no section rule, so the
    // page read as three unrelated things stacked rather than one page. The
    // live status takes the head's right-hand slot, where "Manage" sits on
    // the section above.
    return Semantics(
      button: true,
      label: 'Live Monitoring, $statusLabel',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            label: 'Live Monitoring',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SaStatusDot(color: statusColor, live: monitoring.status == MonitoringConnectionStatus.connected),
                const SizedBox(width: 6),
                Text(statusLabel, style: AppTypography.labelM.copyWith(color: statusColor)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.space3),
          if (latest == null)
            Text(
              monitoring.status == MonitoringConnectionStatus.disconnected
                  ? 'No live device data available.'
                  : 'Waiting for live data…',
              style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.6)),
            )
          else ...[
            Text(latest.summary, style: AppTypography.bodyM.copyWith(color: onSurface)),
            const SizedBox(height: 2),
            Text(
              [
                _formatRelative(latest.timestamp),
                if (latest.hasLocation) '${latest.latitude!.toStringAsFixed(4)}, ${latest.longitude!.toStringAsFixed(4)}',
              ].join(' · '),
              style: AppTypography.labelM.copyWith(color: onSurface.withValues(alpha: 0.5)),
            ),
          ],
          const SizedBox(height: AppSpacing.space3),
          Text('View Live Feed →', style: AppTypography.labelL.copyWith(color: context.saColors.interactive)),
        ],
        ),
      ),
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
                      Text(segment.value.toInt().toString(), style: AppTypography.labelM.copyWith(color: onSurface)),
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
              child: Container(height: 120, decoration: BoxDecoration(borderRadius: AppRadius.xl2Radius, color: Colors.white)),
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
