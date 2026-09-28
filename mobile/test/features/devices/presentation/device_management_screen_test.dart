import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/devices/data/ble_providers.dart';
import 'package:safeher_app/features/devices/data/device_providers.dart';
import 'package:safeher_app/features/devices/data/glove_link_providers.dart';
import 'package:safeher_app/features/devices/domain/device_registration_repository.dart';
import 'package:safeher_app/features/devices/domain/device_repository.dart';
import 'package:safeher_app/features/devices/domain/glove_protocol.dart';
import 'package:safeher_app/features/devices/domain/models/ble_models.dart';
import 'package:safeher_app/features/devices/domain/models/device_detail.dart';
import 'package:safeher_app/features/devices/domain/models/registered_device.dart';
import 'package:safeher_app/features/devices/presentation/device_management_screen.dart';

import 'package:safeher_app/core/local/onboarding_prefs.dart';

import '../../../test_utils/fake_ble_service.dart';
import '../../../test_utils/fake_key_value_store.dart';
import '../../../test_utils/fake_webview_platform.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

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
    sensors: SensorReading(accelG: 1.02, gyroDps: 4.3, heartRateBpm: 0),
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
    sensors: SensorReading(accelG: 1.05, gyroDps: 6.7, heartRateBpm: 42),
  ),
];

class _FakeDeviceRepository implements DeviceRepository {
  @override
  Future<void> unpairDevice(String id) async {}

  _FakeDeviceRepository({this.shouldFail = false});
  final bool shouldFail;

  @override
  Future<List<DeviceDetail>> getDevices() async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (shouldFail) throw Exception('network error');
    return _sampleDevices();
  }
}

class _FakeRegistrationRepository implements DeviceRegistrationRepository {
  @override
  Future<RegisteredDevice> registerDevice({
    required String deviceName,
    required DeviceType deviceType,
  }) async {
    return RegisteredDevice(id: 'srv-1', deviceName: deviceName, deviceType: deviceType, isActive: true);
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

Widget _harness({
  Brightness brightness = Brightness.dark,
  DeviceRepository? repo,
  String? initialLocation,
  FakeBleService? ble,
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      deviceRepositoryProvider.overrideWithValue(repo ?? _FakeDeviceRepository()),
      // The pairing sheet talks to a real radio, which does not exist in a
      // `flutter test` environment — inject the fake instead.
      bleServiceProvider.overrideWithValue(ble ?? FakeBleService()),
      deviceRegistrationRepositoryProvider.overrideWithValue(_FakeRegistrationRepository()),
      // The camera card reads the saved glasses address out of preferences,
      // which are Hive-backed through GetIt and unavailable in a widget test.
      localKeyValueStoreProvider.overrideWithValue(FakeKeyValueStore()),
      ...extraOverrides,
    ],
    child: MaterialApp.router(
    // Mirrors main.dart's shell so screens render over the same ambient
    // field users see; the scaffold background is transparent by design.
    builder: (context, child) =>
        SaAmbientBackground(child: child ?? const SizedBox.shrink()),
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
      // Heart rate, not flex: the glove has a pulse sensor and never had a
      // flex sensor, so the third readout was labelling hardware that does
      // not exist.
      expect(find.text('Heart'), findsOneWidget);
    });

    testWidgets(
      'expanding the glove card shows live confidence alongside Accel/Gyro/Heart Rate',
      (tester) async {
        await tester.pumpWidget(_harness());
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(find.text('Safety Glove'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 500));

        // The glove shows live classification confidence and the derived
        // risk score in place of the 3D visual (which has no meaningful
        // "live" state to show) — shown in addition to the sensor readouts,
        // same as every other device type.
        expect(find.text('CONFIDENCE'), findsOneWidget);
        expect(find.text('RISK SCORE'), findsOneWidget);
        // One placeholder for confidence, one for risk score.
        expect(find.text('--'), findsNWidgets(2));
        expect(find.text('Accel'), findsOneWidget);
        expect(find.text('Gyro'), findsOneWidget);
        expect(find.text('Heart'), findsOneWidget);
        // Existing device controls stay, per the "do not remove" list.
        expect(find.text('Calibrate'), findsOneWidget);
        expect(find.text('Remove Device'), findsOneWidget);
      },
    );

    testWidgets('live confidence updates as the glove sends BLE motion data', (tester) async {
      const deviceId = 'AA:BB:CC:DD:EE:FF';
      const glove = BleDiscoveredDevice(
        id: deviceId,
        advertisedName: 'SafeHer-Glove',
        rssi: -50,
        isConnectable: true,
      );
      final ble = FakeBleService();
      addTearDown(ble.dispose);

      // Motion Risk Score reads GloveLink's state (see
      // motion_data_providers.dart's doc comment on why it no longer opens
      // its own BLE subscription), which subscribes on
      // BlePairingController's connected stage — a real connect through the
      // controller is required, not just connectedGloveIdProvider pointing
      // at an id.
      ble.notifications[GloveBle.classificationCharacteristicUuid] = ['FALL,0.9613'];

      await tester.pumpWidget(_harness(ble: ble));
      await tester.pump(const Duration(milliseconds: 100));

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      // Warm the link provider so its listener is attached before the
      // pairing state moves — exactly as the app does by watching it on
      // screen, and exactly why this is needed: blePairingControllerProvider
      // is autoDispose, and nothing else in this test keeps it alive.
      container.read(gloveLinkProvider);
      container.read(blePairingControllerProvider.notifier).selectDeviceType(DeviceType.glove);
      await container.read(blePairingControllerProvider.notifier).connect(glove);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Safety Glove'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('CONNECTED'), findsOneWidget);
      // 0.9613 confidence, shown rounded to the nearest whole percent — and
      // FALL's severity is 1.0, so the risk score (severity * confidence *
      // 100) numerically coincides with confidence here, giving two '96's.
      expect(find.text('96'), findsNWidgets(2));
      expect(find.text('FALL'), findsOneWidget);

      // Power loss: the glove goes offline without ever sending a final
      // packet, and the last reading must not be left on screen.
      ble.dropConnection(deviceId);
      await tester.pump();
      await tester.pump();
      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.text('--'), findsNWidgets(2));
      expect(find.text('96'), findsNothing);
      expect(find.text('FALL'), findsNothing);

      // Power restored, same physical glove reconnects: a fresh packet
      // updates the display again, and the old FALL reading is not replayed.
      ble.notifications[GloveBle.classificationCharacteristicUuid] = ['SUDDEN_MOVEMENT,0.8000'];
      await tester.runAsync(() async {
        await container.read(blePairingControllerProvider.notifier).connect(glove);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('CONNECTED'), findsOneWidget);
      // Confidence 80, and SUDDEN_MOVEMENT's severity is 0.5, so the risk
      // score (40) is distinct this time.
      expect(find.text('80'), findsOneWidget);
      expect(find.text('40'), findsOneWidget);
      expect(find.text('SUDDEN_MOVEMENT'), findsOneWidget);
      expect(find.text('Devices (2)'), findsOneWidget);
    });

    testWidgets('glove card shows heart rate next to the motion classification', (tester) async {
      const deviceId = 'AA:BB:CC:DD:EE:FF';
      const glove = BleDiscoveredDevice(
        id: deviceId,
        advertisedName: 'SafeHer-Glove',
        rssi: -50,
        isConnectable: true,
      );
      final ble = FakeBleService();
      addTearDown(ble.dispose);
      ble.notifications[GloveBle.classificationCharacteristicUuid] = ['NORMAL,0.9200'];
      ble.notifications[GloveBle.heartRateCharacteristicUuid] = ['BPM,76'];

      await tester.pumpWidget(_harness(ble: ble));
      await tester.pump(const Duration(milliseconds: 100));

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(gloveLinkProvider);
      container.read(blePairingControllerProvider.notifier).selectDeviceType(DeviceType.glove);
      await container.read(blePairingControllerProvider.notifier).connect(glove);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Safety Glove'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));

      // Motion classification is still there, undisturbed...
      expect(find.text('NORMAL'), findsOneWidget);
      expect(find.text('92'), findsOneWidget);
      expect(find.text('RISK SCORE'), findsOneWidget);
      // ...with heart rate alongside it, and honestly labelled as an estimate.
      expect(find.text('HEART RATE'), findsOneWidget);
      expect(find.text('76 BPM'), findsOneWidget);
      expect(find.text('Estimate, not a medical reading'), findsOneWidget);
      expect(find.text('-- BPM'), findsNothing);

      // Power loss: the reading is erased with the connection, and the card
      // says so -- it never falls back to "0 BPM" or the old number.
      ble.dropConnection(deviceId);
      await tester.pump();
      await tester.pump();
      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.text('76 BPM'), findsNothing, reason: 'a stale BPM must not outlive the connection');
      expect(find.text('-- BPM'), findsOneWidget);
      expect(find.text('0 BPM'), findsNothing);
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

    testWidgets('pairing flow: real scan, a genuinely discovered device, connect', (tester) async {
      // The bottom nav bar (added so Devices is a real, always-reachable
      // tab rather than a dead end) occupies a fixed region at the bottom
      // of the viewport — on the default test surface, the "+ Pair
      // Device" card can never scroll clear of it. A taller surface gives
      // the scroll enough room, matching this suite's established pattern
      // for screens combining a long list with the floating nav bar.
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final ble = FakeBleService();
      addTearDown(ble.dispose);
      await tester.pumpWidget(_harness(ble: ble));
      await tester.pump(const Duration(milliseconds: 100));

      // The radar pulse loops forever, so pumpAndSettle would never
      // converge here — bounded pumps throughout this test instead.
      await tester.scrollUntilVisible(find.text('Pair Device'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Pair Device'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Scanning for nearby devices…'), findsOneWidget);
      expect(ble.startScanCalls, 1);

      // Nothing is listed until a peripheral actually advertises.
      ble.emitDevices(const [
        BleDiscoveredDevice(
          id: 'AA:BB:CC:DD:EE:01',
          advertisedName: 'SmartGlove-01',
          rssi: -55,
          isConnectable: true,
        ),
      ]);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('SmartGlove-01'), findsOneWidget);

      await tester.tap(find.text('Connect'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(ble.connectCalls, 1);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('2 GATT services discovered'), findsOneWidget);
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
