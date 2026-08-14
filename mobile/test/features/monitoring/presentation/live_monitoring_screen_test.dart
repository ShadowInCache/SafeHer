import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/devices/data/device_providers.dart';
import 'package:safeher_app/features/monitoring/data/monitoring_providers.dart';
import 'package:safeher_app/features/monitoring/domain/models/realtime_alert_event.dart';
import 'package:safeher_app/features/monitoring/presentation/live_monitoring_screen.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

class _FakeLiveMonitoringController extends LiveMonitoringController {
  _FakeLiveMonitoringController(this._initial);

  final LiveMonitoringState _initial;

  @override
  LiveMonitoringState build() => _initial;
}

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
  LiveMonitoringState? state,
  Size surfaceSize = const Size(390, 844),
}) {
  final resolvedState =
      state ?? const LiveMonitoringState(status: MonitoringConnectionStatus.disconnected, events: []);
  return ProviderScope(
    overrides: [
      liveMonitoringControllerProvider.overrideWith(() => _FakeLiveMonitoringController(resolvedState)),
      devicesProvider.overrideWith((ref) async => const []),
    ],
    child: MediaQuery(
      data: MediaQueryData(size: surfaceSize),
      child: MaterialApp.router(
    // Mirrors main.dart's shell so screens render over the same ambient
    // field users see; the scaffold background is transparent by design.
    builder: (context, child) =>
        SaAmbientBackground(child: child ?? const SizedBox.shrink()),
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        routerConfig: _buildTestRouter(),
      ),
    ),
  );
}

void main() {
  group('LiveMonitoringScreen', () {
    testWidgets('renders_without_exception (connecting state)', (tester) async {
      await tester.pumpWidget(
        _harness(state: const LiveMonitoringState(status: MonitoringConnectionStatus.connecting, events: [])),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('CONNECTING'), findsOneWidget);
    });

    testWidgets('renders_empty_state (disconnected, no device data)', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(find.text('Live Monitoring'), findsOneWidget);
      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.text('No live device data available'), findsOneWidget);
      expect(find.text('Retry Connection'), findsOneWidget);
      expect(find.text('Waiting for live device data'), findsOneWidget);
    });

    testWidgets('renders_with_data (connected with a real received event)', (tester) async {
      final state = LiveMonitoringState(
        status: MonitoringConnectionStatus.connected,
        events: [
          RealtimeAlertEvent(
            kind: RealtimeAlertKind.emergency,
            summary: 'Emergency SOS triggered',
            timestamp: DateTime.now(),
            threatLevel: 'critical',
          ),
        ],
      );
      await tester.pumpWidget(_harness(state: state));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(find.text('LIVE'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Emergency SOS triggered'), 200);
      expect(find.text('Emergency SOS triggered'), findsOneWidget);
      expect(find.textContaining('CRITICAL'), findsOneWidget);
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
