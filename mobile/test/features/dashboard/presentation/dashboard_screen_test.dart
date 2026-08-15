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
import 'package:safeher_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:safeher_app/shared/components/charts/sa_bar_chart.dart';
import 'package:safeher_app/shared/components/charts/sa_donut_chart.dart';
import 'package:safeher_app/shared/components/charts/sa_heat_grid.dart';
import 'package:safeher_app/shared/components/charts/sa_sparkline.dart';
import 'package:safeher_app/shared/components/feedback/sa_progress_ring.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';
import 'package:safeher_app/shared/components/navigation/sa_bottom_nav_bar.dart';

import '../../../test_utils/offline_test_overrides.dart';

DashboardAnalytics _sampleAnalytics({
  int totalIncidents = 47,
  double? trendPct = 18.5,
  List<SaHeatCell> heatCells = const [
    SaHeatCell(lat: 17.38, lng: 78.48, weight: 4),
    SaHeatCell(lat: 17.41, lng: 78.47, weight: 1),
  ],
  List<DeviceHealth> devices = const [
    DeviceHealth(
      deviceId: 'dev_1',
      deviceName: 'Smart Glove',
      deviceType: 'glove',
      batteryLevel: 82,
      signalStrength: -54,
      isActive: true,
      lastSeen: null,
    ),
  ],
}) {
  final anchor = DateTime(2026, 8, 15);
  return DashboardAnalytics(
    totalIncidents: totalIncidents,
    trendPct: trendPct,
    incidentSparkline: List<double>.generate(30, (i) => (i % 5).toDouble()),
    threatDays: [
      for (var i = 0; i < 14; i++)
        ThreatDay(
          date: anchor.subtract(Duration(days: 13 - i)),
          total: i == 13 ? 3 : (i % 3),
          counts: i == 13 ? const {'critical': 1, 'medium': 2} : const {'low': 1},
        ),
    ],
    heatCells: heatCells,
    confidenceBreakdown: const [
      SaDonutSegment(label: 'high', value: 4, color: Colors.orange),
      SaDonutSegment(label: 'low', value: 8, color: Colors.green),
    ],
    recentIncidents: [
      RecentIncident(
        id: 'inc_1',
        title: 'Emergency SOS',
        threatLevel: 'critical',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
    ],
    deviceHealth: devices,
    batteryHistoryAvailable: false,
    safetyScore: const SafetyScore(score: 76, windowDays: 7, incidentFreeStreakDays: 3),
  );
}

class _FakeDashboardRepository implements DashboardRepository {
  _FakeDashboardRepository({this.analytics, this.shouldFail = false});

  final DashboardAnalytics? analytics;
  final bool shouldFail;

  @override
  Future<DashboardSummary> getDashboardSummary() =>
      throw UnimplementedError('The Dashboard screen reads analytics, not the Home summary.');

  @override
  Future<DashboardAnalytics> getDashboardAnalytics() async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (shouldFail) throw Exception('network error');
    return analytics ?? _sampleAnalytics();
  }
}

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/dashboard',
    routes: [
      GoRoute(path: '/dashboard', builder: (context, state) => const DashboardScreen()),
      GoRoute(path: '/home', builder: (context, state) => const Scaffold(body: Text('home-stub'))),
      GoRoute(path: '/monitor', builder: (context, state) => const Scaffold(body: Text('monitor-stub'))),
      GoRoute(path: '/profile', builder: (context, state) => const Scaffold(body: Text('profile-stub'))),
      GoRoute(path: '/devices', builder: (context, state) => const Scaffold(body: Text('devices-stub'))),
      GoRoute(path: '/reports', builder: (context, state) => const Scaffold(body: Text('reports-stub'))),
      GoRoute(path: '/emergency', builder: (context, state) => const Scaffold(body: Text('emergency-stub'))),
    ],
  );
}

Widget _harness({
  Brightness brightness = Brightness.dark,
  DashboardRepository? repo,
}) {
  return ProviderScope(
    overrides: [
      dashboardRepositoryProvider.overrideWithValue(repo ?? _FakeDashboardRepository()),
      ...offlineTestOverrides(),
    ],
    child: MaterialApp.router(
      builder: (context, child) => SaAmbientBackground(child: child ?? const SizedBox.shrink()),
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      debugShowCheckedModeBanner: false,
      routerConfig: _buildTestRouter(),
    ),
  );
}

/// Cards stagger in 50ms apart, so nothing is on screen at t=0. Every test
/// that asserts on content has to clear the whole ladder first.
Future<void> _settleCards(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  group('DashboardScreen', () {
    testWidgets('renders every SRS card once analytics resolve', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await _settleCards(tester);

      expect(find.text('TOTAL INCIDENTS'), findsOneWidget);
      expect(find.text('47'), findsOneWidget);
      expect(find.byType(SaSparkline), findsOneWidget);
      expect(find.text('THREAT ANALYTICS'), findsOneWidget);
      expect(find.byType(SaBarChart), findsOneWidget);
      expect(find.byType(SaHeatGrid), findsOneWidget);

      // The lower two rows sit below the fold on a 390x844 surface.
      await tester.scrollUntilVisible(find.byType(SaProgressRing), 300);
      expect(find.text('SEVERITY MIX'), findsOneWidget);
      expect(find.text('RECENT REPORTS'), findsOneWidget);
      expect(find.text('DEVICE HEALTH'), findsOneWidget);
      expect(find.text('SAFETY SCORE'), findsOneWidget);
    });

    testWidgets('shows a shimmer skeleton before data lands', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();

      expect(find.byType(SaBarChart), findsNothing);
      expect(find.text('TOTAL INCIDENTS'), findsNothing);

      // Drain the repository's pending delay so the binding doesn't fail
      // the test on a leftover timer.
      await _settleCards(tester);
    });

    testWidgets('offers a retry when the aggregation fails', (tester) async {
      await tester.pumpWidget(_harness(repo: _FakeDashboardRepository(shouldFail: true)));
      await _settleCards(tester);

      expect(find.text('Couldn’t load your dashboard'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('empty account gets an empty state, not a page of zeroes', (tester) async {
      await tester.pumpWidget(
        _harness(
          repo: _FakeDashboardRepository(
            analytics: _sampleAnalytics(totalIncidents: 0, heatCells: const [], devices: const []),
          ),
        ),
      );
      await _settleCards(tester);

      expect(find.text('Nothing to report'), findsOneWidget);
      expect(find.byType(SaBarChart), findsNothing);
    });

    testWidgets('says so when there is no prior period to trend against', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _harness(repo: _FakeDashboardRepository(analytics: _sampleAnalytics(trendPct: null))),
      );
      await _settleCards(tester);

      // A null trend must never render as "0.0%", which would read as a
      // measured result rather than an absent one.
      expect(find.text('No prior period'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('tapping a bar opens that day’s breakdown', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await _settleCards(tester);

      // The last bar is the sample's busy day: 1 critical + 2 medium.
      final chart = tester.getRect(find.byType(SaBarChart));
      await tester.tapAt(Offset(chart.right - 12, chart.center.dy));
      // Not pumpAndSettle: the sheet shows a critical SaThreatChip, whose
      // danger-level pulse repeats indefinitely.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('3 incidents recorded.'), findsOneWidget);
      expect(find.text('1 × critical'), findsOneWidget);
      expect(find.text('2 × medium'), findsOneWidget);
    });

    testWidgets('battery is labelled current, not a trend, while history is absent', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await _settleCards(tester);
      await tester.scrollUntilVisible(find.text('DEVICE HEALTH'), 300);

      expect(find.text('Current battery'), findsOneWidget);
      expect(find.text('Battery trend'), findsNothing);
    });

    testWidgets('navigation_actions_work: bottom nav tabs switch routes', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await _settleCards(tester);

      await tester.tap(
        find.descendant(of: find.byType(SaBottomNavBar), matching: find.bySemanticsLabel('Monitor')),
      );
      await tester.pumpAndSettle();
      expect(find.text('monitor-stub'), findsOneWidget);
    });

    testWidgets('navigation_actions_work: SOS FAB navigates to emergency', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await _settleCards(tester);

      await tester.tap(find.bySemanticsLabel('SOS emergency'));
      await tester.pumpAndSettle();
      expect(find.text('emergency-stub'), findsOneWidget);
    });

    testWidgets('renders in light mode without exceptions', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness(brightness: Brightness.light));
      await _settleCards(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('TOTAL INCIDENTS'), findsOneWidget);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        _harness(brightness: Brightness.light),
        surfaceSize: const Size(390, 844),
      );
      await _settleCards(tester);
      await screenMatchesGolden(
        tester,
        'dashboard_screen_light',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
      await _settleCards(tester);
      await screenMatchesGolden(
        tester,
        'dashboard_screen_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });
  });

  group('SaHeatGrid', () {
    testWidgets('renders with no cells', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: SaHeatGrid(cells: [])),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('describes its contents to a screen reader', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: SaHeatGrid(
              cells: [
                SaHeatCell(lat: 17.38, lng: 78.48, weight: 4),
                SaHeatCell(lat: 17.41, lng: 78.47, weight: 1),
              ],
            ),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel('Incident location map, 5 incident locations across 2 areas'),
        findsOneWidget,
      );
    });

    testWidgets('survives a single cell without dividing by a zero span', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: SaHeatGrid(cells: [SaHeatCell(lat: 17.38, lng: 78.48, weight: 3)]),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
