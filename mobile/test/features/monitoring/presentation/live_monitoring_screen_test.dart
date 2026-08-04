import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/monitoring/data/monitoring_providers.dart';
import 'package:safeher_app/features/monitoring/domain/models/monitoring_snapshot.dart';
import 'package:safeher_app/features/monitoring/presentation/live_monitoring_screen.dart';
import 'package:safeher_app/shared/components/charts/sa_motion_chart.dart';

MonitoringSnapshot _sampleSnapshot() => MonitoringSnapshot(
  threatScore: 0.42,
  waveform: List.generate(64, (i) => 0.2 + (i % 8) * 0.05),
  dbLevel: 48,
  detectedEmotion: 'calm',
  motionWindow: List.generate(30, (i) => MotionSample(x: i * 0.1, y: 0.2, z: 0.1)),
  eventPins: const [MotionEventPin(sampleIndex: 10, label: 'Motion spike', timestamp: '10:00:00')],
  glassesConnected: false,
);

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/monitor',
    routes: [
      GoRoute(path: '/monitor', builder: (context, state) => const LiveMonitoringScreen()),
      GoRoute(path: '/home', builder: (context, state) => const Scaffold(body: Text('home-stub'))),
      GoRoute(path: '/devices', builder: (context, state) => const Scaffold(body: Text('devices-stub'))),
    ],
  );
}

Widget _harness({
  Brightness brightness = Brightness.dark,
  Stream<MonitoringSnapshot>? stream,
  Size surfaceSize = const Size(390, 844),
}) {
  return ProviderScope(
    overrides: [
      monitoringStreamProvider.overrideWith((ref) => stream ?? Stream.value(_sampleSnapshot())),
    ],
    child: MediaQuery(
      data: MediaQueryData(size: surfaceSize),
      child: MaterialApp.router(
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        routerConfig: _buildTestRouter(),
      ),
    ),
  );
}

void main() {
  group('LiveMonitoringScreen', () {
    testWidgets('renders_without_exception (loading state)', (tester) async {
      await tester.pumpWidget(_harness(stream: const Stream.empty()));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders_with_data (mocked stream)', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(find.text('Live Monitoring'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('Audio'), findsOneWidget);
      expect(find.text('Motion'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Connect glasses'), findsOneWidget);
    });

    testWidgets('renders_error_state (retry)', (tester) async {
      await tester.pumpWidget(_harness(stream: Stream.error(Exception('stream error'))));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(find.text("Couldn't start live monitoring"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(_harness(brightness: Brightness.light));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders 2-column layout on tablet width', (tester) async {
      await tester.pumpWidget(_harness(surfaceSize: const Size(900, 1024)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(find.text('Audio'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
    });

    testWidgets('navigation_actions_work: back button returns to home', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('home-stub'), findsOneWidget);
    });

    testWidgets('navigation_actions_work: connect glasses CTA goes to devices', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Connect glasses'));
      await tester.pumpAndSettle();
      expect(find.text('devices-stub'), findsOneWidget);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(_harness(brightness: Brightness.light), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 50));
      await screenMatchesGolden(
        tester,
        'live_monitoring_screen_light',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 50)),
      );
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 50));
      await screenMatchesGolden(
        tester,
        'live_monitoring_screen_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 50)),
      );
    });
  });
}
