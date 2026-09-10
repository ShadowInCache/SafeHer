import 'dart:convert';

import 'dart:typed_data';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/dashboard/data/dashboard_providers.dart';
import 'package:safeher_app/features/dashboard/domain/dashboard_repository.dart';
import 'package:safeher_app/features/dashboard/domain/models/dashboard_analytics.dart';
import 'package:safeher_app/features/dashboard/domain/models/dashboard_summary.dart';
import 'package:safeher_app/features/devices/data/device_providers.dart';
import 'package:safeher_app/features/devices/domain/device_repository.dart';
import 'package:safeher_app/features/devices/domain/models/device_detail.dart';
import 'package:safeher_app/features/home/data/home_providers.dart';
import 'package:safeher_app/features/home/domain/home_repository.dart';
import 'package:safeher_app/features/home/domain/models/home_summary.dart';
import 'package:safeher_app/features/home/presentation/home_screen.dart';
import 'package:safeher_app/features/monitoring/data/monitoring_providers.dart';
import 'package:safeher_app/features/profile/data/profile_providers.dart';
import 'package:safeher_app/features/profile/domain/models/user_profile.dart';
import 'package:safeher_app/features/profile/domain/profile_repository.dart';
import 'package:safeher_app/features/reports/data/reports_providers.dart';
import 'package:safeher_app/features/reports/domain/models/report_detail.dart';
import 'package:safeher_app/features/reports/domain/models/report_summary.dart';
import 'package:safeher_app/features/reports/domain/reports_repository.dart';
import 'package:safeher_app/shared/components/charts/sa_bar_chart.dart';
import 'package:safeher_app/shared/components/navigation/sa_bottom_nav_bar.dart';
import 'package:safeher_app/shared/models/threat_level.dart';

import '../../../test_utils/offline_test_overrides.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

HomeSummary _sampleSummary() {
  return HomeSummary(
    threat: ThreatSnapshot(
      score: 0.28,
      motionScore: 0.2,
      audioScore: 0.15,
      visionScore: 0.35,
      lastUpdated: DateTime.now().subtract(const Duration(minutes: 2)),
    ),
  );
}

class _FakeHomeRepository implements HomeRepository {
  _FakeHomeRepository({this.shouldFail = false});
  final bool shouldFail;

  @override
  Future<HomeSummary> getHomeSummary() async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (shouldFail) throw Exception('network error');
    return _sampleSummary();
  }
}

class _FakeProfileRepository implements ProfileRepository {
  @override
  Future<UserProfile> getUserProfile() async {
    await Future.delayed(const Duration(milliseconds: 50));
    return const UserProfile(
      name: 'Priya Patel',
      email: 'priya.patel@example.com',
      phone: '+1 555 123 4567',
      memberSince: 'March 2025',
      safetyScore: 87,
      streakDays: 12,
    );
  }

  @override
  Future<UserProfile> updateProfile({String? name, String? phone, double? threatThreshold}) => throw UnimplementedError();

  @override
  Future<List<int>> exportMyData() async => utf8.encode('{"account":{}}');
}

class _FakeDeviceRepository implements DeviceRepository {
  @override
  Future<void> unpairDevice(String id) async {}

  @override
  Future<List<DeviceDetail>> getDevices() async {
    await Future.delayed(const Duration(milliseconds: 50));
    return [
      DeviceDetail(
        id: 'ring',
        name: 'Smart Ring',
        type: DeviceType.ring,
        isOnline: true,
        batteryPercent: 0.82,
        batteryHoursRemaining: 36,
        signalStrength: 3,
        firmwareVersion: 'v2.4.1',
        updateAvailable: false,
        sensors: const SensorReading(accelG: 1.02, gyroDps: 4.3, heartRateBpm: 0),
        lastSeen: DateTime.now().subtract(const Duration(seconds: 30)),
      ),
    ];
  }
}

class _FakeReportsRepository implements ReportsRepository {
  var exportCalls = <String>[];
  var shareCalls = <String>[];

  /// Set to make both actions fail, as a network error would.
  bool actionsFail = false;

  @override
  Future<Uint8List> exportPdf(String incidentId) async {
    exportCalls.add(incidentId);
    if (actionsFail) throw Exception('export failed');
    return Uint8List.fromList('%PDF-1.4 fake'.codeUnits);
  }

  @override
  Future<String> createShareLink(String incidentId) async {
    shareCalls.add(incidentId);
    if (actionsFail) throw Exception('share failed');
    return 'https://example.invalid/api/v1/share/token-$incidentId';
  }

  @override
  Future<List<ReportSummary>> getReports() async {
    await Future.delayed(const Duration(milliseconds: 50));
    return const [
      ReportSummary(
        id: '1',
        date: '2h ago',
        type: 'Elevated motion detected',
        level: ThreatLevel.elevated,
        summarySnippet: 'Sudden acceleration spike near Elm Street.',
      ),
    ];
  }

  @override
  Future<ReportDetail> getReportDetail(String id) => throw UnimplementedError();
}

class _FakeDashboardRepository implements DashboardRepository {
  @override
  Future<DashboardSummary> getDashboardSummary() async {
    await Future.delayed(const Duration(milliseconds: 50));
    return const DashboardSummary(
      weeklyThreatTrend: [
        SaBarChartDatum(label: 'Mon', value: 0, level: ThreatLevel.safe),
        SaBarChartDatum(label: 'Tue', value: 1, level: ThreatLevel.caution),
      ],
      eventBreakdown: [],
    );
  }

  @override
  Future<DashboardAnalytics> getDashboardAnalytics() =>
      throw UnimplementedError('Home reads the weekly summary, not the analytics aggregation.');
}

class _FakeLiveMonitoringController extends LiveMonitoringController {
  @override
  LiveMonitoringState build() => const LiveMonitoringState(status: MonitoringConnectionStatus.connected, events: []);
}

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      GoRoute(path: '/monitor', builder: (context, state) => const Scaffold(body: Text('monitor-stub'))),
      GoRoute(path: '/devices', builder: (context, state) => const Scaffold(body: Text('devices-stub'))),
      GoRoute(path: '/dashboard', builder: (context, state) => const Scaffold(body: Text('dashboard-stub'))),
      GoRoute(path: '/profile', builder: (context, state) => const Scaffold(body: Text('profile-stub'))),
      GoRoute(path: '/emergency', builder: (context, state) => const Scaffold(body: Text('emergency-stub'))),
      GoRoute(path: '/search', builder: (context, state) => const Scaffold(body: Text('search-stub'))),
      GoRoute(path: '/reports', builder: (context, state) => const Scaffold(body: Text('reports-stub'))),
      GoRoute(
        path: '/reports/:id',
        builder: (context, state) => Scaffold(body: Text('report-${state.pathParameters['id']}-stub')),
      ),
      GoRoute(
        path: '/devices/:id',
        builder: (context, state) => Scaffold(body: Text('device-${state.pathParameters['id']}-stub')),
      ),
    ],
  );
}

Widget _harness({Brightness brightness = Brightness.dark, HomeRepository? repo, bool offline = false}) {
  return ProviderScope(
    overrides: [
      homeRepositoryProvider.overrideWithValue(repo ?? _FakeHomeRepository()),
      profileRepositoryProvider.overrideWithValue(_FakeProfileRepository()),
      deviceRepositoryProvider.overrideWithValue(_FakeDeviceRepository()),
      reportsRepositoryProvider.overrideWithValue(_FakeReportsRepository()),
      dashboardRepositoryProvider.overrideWithValue(_FakeDashboardRepository()),
      liveMonitoringControllerProvider.overrideWith(() => _FakeLiveMonitoringController()),
      ...offlineTestOverrides(offline: offline),
    ],
    child: MaterialApp.router(
    // Mirrors main.dart's shell so screens render over the same ambient
    // field users see; the scaffold background is transparent by design.
    builder: (context, child) =>
        SaAmbientBackground(child: child ?? const SizedBox.shrink()),
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      routerConfig: _buildTestRouter(),
    ),
  );
}

void main() {
  group('HomeScreen', () {
    testWidgets('renders_without_exception (loading state)', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Flush the mock repositories' Future.delayed so their timers don't
      // leak past this test's teardown.
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('renders_with_data (mocked repository)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Priya'), findsOneWidget);
      expect(find.text("You're Safe"), findsOneWidget);
      expect(find.text('Smart Ring'), findsOneWidget);

      // Section headers render as uppercase eyebrows ("THIS WEEK"); the
      // sentence-case string survives as the Semantics label, which is what
      // a screen reader announces.
      await tester.scrollUntilVisible(find.text('THIS WEEK'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('THIS WEEK'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('RECENT ALERTS'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('RECENT ALERTS'), findsOneWidget);
    });

    testWidgets('renders_empty_state (no devices shows connect prompt, not fake data)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeRepositoryProvider.overrideWithValue(_FakeHomeRepository()),
            profileRepositoryProvider.overrideWithValue(_FakeProfileRepository()),
            deviceRepositoryProvider.overrideWithValue(_EmptyDeviceRepository()),
            reportsRepositoryProvider.overrideWithValue(_FakeReportsRepository()),
            dashboardRepositoryProvider.overrideWithValue(_FakeDashboardRepository()),
            liveMonitoringControllerProvider.overrideWith(() => _FakeLiveMonitoringController()),
            ...offlineTestOverrides(),
          ],
          child: MaterialApp.router(theme: AppTheme.dark, routerConfig: _buildTestRouter()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('No Wearable Connected'), findsOneWidget);
      expect(find.text('Connect Device'), findsOneWidget);
    });

    testWidgets('renders_error_state (error + retry)', (tester) async {
      await tester.pumpWidget(_harness(repo: _FakeHomeRepository(shouldFail: true)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text("Couldn't load your dashboard"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(_harness(brightness: Brightness.light));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('navigation_actions_work: device row navigates to device detail', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Smart Ring'));
      await tester.pumpAndSettle();
      expect(find.text('device-ring-stub'), findsOneWidget);
    });

    testWidgets('navigation_actions_work: SOS quick action navigates to emergency', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));

      // The nav bar's SOS FAB is icon-only (no "SOS" text), so this
      // uniquely targets the quick-action tile's visible label.
      await tester.scrollUntilVisible(
        find.text('SOS'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('SOS'));
      await tester.pumpAndSettle();
      expect(find.text('emergency-stub'), findsOneWidget);
    });

    testWidgets('navigation_actions_work: SOS FAB navigates to emergency', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.bySemanticsLabel('SOS emergency'));
      await tester.pumpAndSettle();
      expect(find.text('emergency-stub'), findsOneWidget);
    });

    testWidgets('navigation_actions_work: View Live Feed navigates to monitor', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.scrollUntilVisible(find.text('View Live Feed →'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('View Live Feed →'));
      await tester.pumpAndSettle();
      expect(find.text('monitor-stub'), findsOneWidget);
    });

    testWidgets('navigation_actions_work: alert card navigates to report detail', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.scrollUntilVisible(find.text('Elevated motion detected'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Elevated motion detected'));
      await tester.pumpAndSettle();
      expect(find.text('report-1-stub'), findsOneWidget);
    });

    testWidgets('navigation_actions_work: bottom nav Dashboard tab switches routes', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));

      // Scoped to the nav bar: a "Dashboard" heading elsewhere in the
      // scrolled content would produce the same implicit text semantics.
      await tester.tap(
        find.descendant(of: find.byType(SaBottomNavBar), matching: find.bySemanticsLabel('Dashboard')),
      );
      await tester.pumpAndSettle();
      expect(find.text('dashboard-stub'), findsOneWidget);
    });

    testWidgets('navigation_actions_work: search button navigates to search', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.bySemanticsLabel('Search'));
      await tester.pumpAndSettle();
      expect(find.text('search-stub'), findsOneWidget);
    });

    testWidgets('slides the offline banner into view when connectivity is down', (tester) async {
      await tester.pumpWidget(_harness(offline: true));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      expect(find.textContaining("You're offline"), findsOneWidget);

      final slide = tester.widget<AnimatedSlide>(find.byKey(const ValueKey('offline-banner-slide')));
      expect(slide.offset, Offset.zero);
    });

    testWidgets('slides the offline banner out of view when connectivity is up', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);

      final slide = tester.widget<AnimatedSlide>(find.byKey(const ValueKey('offline-banner-slide')));
      expect(slide.offset, isNot(Offset.zero));
    });

    // Home renders a greeting that depends on the hour and a date that
    // depends on the day, so these goldens quietly encoded the moment they
    // were generated: they passed all morning, failed after noon, and would
    // have failed again tomorrow when the date rolled over. Pinning the clock
    // is what makes them a regression net instead of a calendar.
    final fixedNow = DateTime(2026, 8, 24, 9, 41);

    testGoldens('golden - light', (tester) async {
      await withClock(Clock.fixed(fixedNow), () async {
        await tester.pumpWidgetBuilder(_harness(brightness: Brightness.light), surfaceSize: const Size(390, 844));
        await tester.pump(const Duration(milliseconds: 100));
        await screenMatchesGolden(
          tester,
          'home_screen_light',
          customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
        );
      });
    });

    testGoldens('golden - dark', (tester) async {
      await withClock(Clock.fixed(fixedNow), () async {
        await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
        await tester.pump(const Duration(milliseconds: 100));
        await screenMatchesGolden(
          tester,
          'home_screen_dark',
          customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
        );
      });
    });
  });
}

class _EmptyDeviceRepository implements DeviceRepository {
  @override
  Future<void> unpairDevice(String id) async {}

  @override
  Future<List<DeviceDetail>> getDevices() async {
    await Future.delayed(const Duration(milliseconds: 50));
    return const [];
  }
}
