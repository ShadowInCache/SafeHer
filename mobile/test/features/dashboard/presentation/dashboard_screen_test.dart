import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_colors.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/dashboard/data/dashboard_providers.dart';
import 'package:safeher_app/features/dashboard/domain/dashboard_repository.dart';
import 'package:safeher_app/features/dashboard/domain/models/dashboard_summary.dart';
import 'package:safeher_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:safeher_app/shared/components/cards/sa_stat_card.dart';
import 'package:safeher_app/shared/components/charts/sa_bar_chart.dart';
import 'package:safeher_app/shared/components/charts/sa_donut_chart.dart';
import 'package:safeher_app/shared/models/threat_level.dart';

DashboardSummary _sampleSummary() => DashboardSummary(
  stats: const [
    DashboardStatItem(label: 'Total Alerts', value: '14', trend: SaTrendDirection.down),
    DashboardStatItem(label: 'Avg Response', value: '42s', trend: SaTrendDirection.up),
    DashboardStatItem(label: 'Safe Streak', value: '12d', trend: SaTrendDirection.up),
    DashboardStatItem(label: 'Resolved', value: '11/14', trend: SaTrendDirection.flat),
  ],
  weeklyThreatTrend: [
    for (final label in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
      SaBarChartDatum(label: label, value: 0.3, level: ThreatLevel.caution),
  ],
  eventBreakdown: const [
    SaDonutSegment(label: 'Motion', value: 6, color: AppColors.violet500),
    SaDonutSegment(label: 'Audio', value: 4, color: AppColors.coral500),
  ],
  safetyScoreTrend: const [72, 75, 70, 78, 82, 85, 80],
  locationHeatGrid: const [
    [0.1, 0.4],
    [0.3, 0.6],
  ],
);

class _FakeDashboardRepository implements DashboardRepository {
  _FakeDashboardRepository({this.shouldFail = false});
  final bool shouldFail;

  @override
  Future<DashboardSummary> getDashboardSummary() async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (shouldFail) throw Exception('network error');
    return _sampleSummary();
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
      GoRoute(path: '/emergency', builder: (context, state) => const Scaffold(body: Text('emergency-stub'))),
    ],
  );
}

Widget _harness({Brightness brightness = Brightness.dark, DashboardRepository? repo}) {
  return ProviderScope(
    overrides: [dashboardRepositoryProvider.overrideWithValue(repo ?? _FakeDashboardRepository())],
    child: MaterialApp.router(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      routerConfig: _buildTestRouter(),
    ),
  );
}

void main() {
  group('DashboardScreen', () {
    testWidgets('renders_without_exception (loading state)', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('renders_with_data (mocked repository)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 1700));
      expect(tester.takeException(), isNull);
      expect(find.text('Dashboard'), findsNWidgets(2)); // screen title + active nav tab label
      expect(find.text('Total Alerts'), findsOneWidget);
      expect(find.text('Weekly Threat Trend'), findsOneWidget);
      expect(find.text('Event Breakdown'), findsOneWidget);
      expect(find.text('Safety Score Trend'), findsOneWidget);
      expect(find.text('Incident Heat Grid'), findsOneWidget);
    });

    testWidgets('renders_empty_state (error + retry)', (tester) async {
      await tester.pumpWidget(_harness(repo: _FakeDashboardRepository(shouldFail: true)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text("Couldn't load your dashboard"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(_harness(brightness: Brightness.light));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 1700));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 1700));
      expect(tester.takeException(), isNull);
    });

    testWidgets('navigation_actions_work: bottom nav tabs switch routes', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.bySemanticsLabel('Home'));
      await tester.pumpAndSettle();
      expect(find.text('home-stub'), findsOneWidget);
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

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(_harness(brightness: Brightness.light), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(
        tester,
        'dashboard_screen_light',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 1700)),
      );
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(
        tester,
        'dashboard_screen_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 1700)),
      );
    });
  });
}
