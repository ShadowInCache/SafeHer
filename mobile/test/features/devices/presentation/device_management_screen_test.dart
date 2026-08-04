import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/devices/data/device_providers.dart';
import 'package:safeher_app/features/devices/domain/device_repository.dart';
import 'package:safeher_app/features/devices/domain/models/device_detail.dart';
import 'package:safeher_app/features/devices/presentation/device_management_screen.dart';

import '../../../test_utils/fake_webview_platform.dart';

List<DeviceDetail> _sampleDevices() => const [
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
    sensors: SensorReading(accelG: 1.02, gyroDps: 4.3, flexPercent: 0),
  ),
  DeviceDetail(
    id: 'glove',
    name: 'Safety Glove',
    type: DeviceType.glove,
    isOnline: true,
    batteryPercent: 0.64,
    batteryHoursRemaining: 14,
    signalStrength: 3,
    firmwareVersion: 'v1.2.3',
    updateAvailable: true,
    sensors: SensorReading(accelG: 1.05, gyroDps: 6.7, flexPercent: 42),
  ),
];

class _FakeDeviceRepository implements DeviceRepository {
  _FakeDeviceRepository({this.shouldFail = false});
  final bool shouldFail;

  @override
  Future<List<DeviceDetail>> getDevices() async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (shouldFail) throw Exception('network error');
    return _sampleDevices();
  }
}

GoRouter _buildTestRouter({String? initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation ?? '/devices',
    routes: [
      GoRoute(path: '/devices', builder: (context, state) => const DeviceManagementScreen()),
      GoRoute(
        path: '/devices/:id',
        builder: (context, state) => DeviceManagementScreen(initialExpandedId: state.pathParameters['id']),
      ),
      GoRoute(path: '/home', builder: (context, state) => const Scaffold(body: Text('home-stub'))),
    ],
  );
}

Widget _harness({Brightness brightness = Brightness.dark, DeviceRepository? repo, String? initialLocation}) {
  return ProviderScope(
    overrides: [deviceRepositoryProvider.overrideWithValue(repo ?? _FakeDeviceRepository())],
    child: MaterialApp.router(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      routerConfig: _buildTestRouter(initialLocation: initialLocation),
    ),
  );
}

void main() {
  setUpAll(FakeWebViewPlatform.install);

  group('DeviceManagementScreen', () {
    testWidgets('renders_without_exception (loading state)', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('renders_with_data (mocked repository)', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('Devices (2)'), findsOneWidget);
      expect(find.text('Smart Ring'), findsOneWidget);
      expect(find.text('Safety Glove'), findsOneWidget);
      expect(find.text('Pair Device'), findsOneWidget);
    });

    testWidgets('renders_empty_state (error + retry)', (tester) async {
      await tester.pumpWidget(_harness(repo: _FakeDeviceRepository(shouldFail: true)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text("Couldn't load your devices"), findsOneWidget);
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

    testWidgets('handles tap to expand a card revealing 3D visual and sensors', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Calibrate'), findsNothing);
      await tester.tap(find.text('Smart Ring'));
      await tester.pump(const Duration(milliseconds: 300));
      // 3D visual shows a shimmer for 400ms before swapping to the viewer.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Calibrate'), findsOneWidget);
      expect(find.text('Accel'), findsOneWidget);
      expect(find.text('Gyro'), findsOneWidget);
      expect(find.text('Flex'), findsOneWidget);
    });

    testWidgets('deep link with initialExpandedId auto-expands that device', (tester) async {
      await tester.pumpWidget(_harness(initialLocation: '/devices/glove'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Calibrate'), findsOneWidget);
    });

    testWidgets('navigation_actions_work: back button returns to home', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('home-stub'), findsOneWidget);
    });

    testWidgets('full pairing flow: scan, find devices, enter PIN, success toast', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));

      // The radar pulse loops forever, so pumpAndSettle would never
      // converge here — bounded pumps throughout this test instead.
      await tester.tap(find.text('Pair Device'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Scanning for nearby devices…'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.textContaining('SafeHer Ring'), findsOneWidget);

      await tester.tap(find.text('Pair').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Enter Pairing PIN'), findsOneWidget);

      final otpFields = find.byType(TextField);
      for (var i = 0; i < 6; i++) {
        await tester.enterText(otpFields.at(i), '$i');
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('paired!'), findsOneWidget);
      // Flush the toast's own dismiss timers so nothing leaks past teardown.
      await tester.pump(const Duration(seconds: 5));
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(_harness(brightness: Brightness.light), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(
        tester,
        'device_management_screen_light',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(
        tester,
        'device_management_screen_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });
  });
}
