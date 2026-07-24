import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/home/data/home_providers.dart';
import 'package:safeher_app/features/home/domain/home_repository.dart';
import 'package:safeher_app/features/home/domain/models/home_summary.dart';
import 'package:safeher_app/features/home/presentation/home_screen.dart';
import 'package:safeher_app/shared/components/cards/sa_stat_card.dart';
import 'package:safeher_app/shared/models/threat_level.dart';

HomeSummary _sampleSummary() {
  return HomeSummary(
    userName: 'Priya',
    hasUnreadAlerts: true,
    threat: ThreatSnapshot(
      score: 0.28,
      motionScore: 0.2,
      audioScore: 0.15,
      visionScore: 0.35,
      lastUpdated: DateTime.now().subtract(const Duration(minutes: 2)),
    ),
    devices: const [
      DeviceSummary(id: 'ring', name: 'Smart Ring', batteryPercent: 0.82, signalStrength: 3, isOnline: true),
      DeviceSummary(id: 'glasses', name: 'Safety Glasses', batteryPercent: 0.46, signalStrength: 2, isOnline: true),
    ],
    waveformPreview: List.generate(32, (i) => (i % 6) / 8),
    motionPreview: List.generate(30, (i) => 0.4 + 0.1 * i),
    recentAlerts: const [
      AlertSummary(
        id: '1',
        title: 'Elevated motion detected',
        timestamp: '2h ago',
        level: ThreatLevel.elevated,
        summary: 'Sudden acceleration spike near Elm Street.',
      ),
    ],
    safetyScore: const SafetyScoreSummary(score: 87, streakDays: 12, trend: SaTrendDirection.up),
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

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      GoRoute(path: '/monitor', builder: (context, state) => const Scaffold(body: Text('monitor-stub'))),
      GoRoute(path: '/dashboard', builder: (context, state) => const Scaffold(body: Text('dashboard-stub'))),
      GoRoute(path: '/profile', builder: (context, state) => const Scaffold(body: Text('profile-stub'))),
      GoRoute(path: '/emergency', builder: (context, state) => const Scaffold(body: Text('emergency-stub'))),
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

Widget _harness({Brightness brightness = Brightness.dark, HomeRepository? repo}) {
  return ProviderScope(
    overrides: [homeRepositoryProvider.overrideWithValue(repo ?? _FakeHomeRepository())],
    child: MaterialApp.router(
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
      // Flush the mock repository's Future.delayed so its timer doesn't
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
      expect(find.text('Smart Ring'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Recent Alerts'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Recent Alerts'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Daily Safety Score'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Daily Safety Score'), findsOneWidget);
    });

    testWidgets('renders_empty_state (error + retry)', (tester) async {
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

    testWidgets('navigation_actions_work: device card navigates to device detail', (tester) async {
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

    testWidgets('navigation_actions_work: bottom nav tabs switch routes', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.bySemanticsLabel('Dashboard'));
      await tester.pumpAndSettle();
      expect(find.text('dashboard-stub'), findsOneWidget);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(_harness(brightness: Brightness.light), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(
        tester,
        'home_screen_light',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(
        tester,
        'home_screen_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });
  });
}
