import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/network/api_exception.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/devices/data/ble_providers.dart';
import 'package:safeher_app/features/devices/data/device_providers.dart';
import 'package:safeher_app/features/devices/domain/device_registration_repository.dart';
import 'package:safeher_app/features/devices/domain/device_repository.dart';
import 'package:safeher_app/features/devices/domain/models/ble_models.dart';
import 'package:safeher_app/features/devices/domain/models/device_detail.dart';
import 'package:safeher_app/features/devices/domain/models/registered_device.dart';
import 'package:safeher_app/features/devices/presentation/widgets/ble_pairing_sheet.dart';

import '../../../../test_utils/fake_ble_service.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

/// A named peripheral with a strong signal.
const _named = BleDiscoveredDevice(
  id: 'AA:BB:CC:DD:EE:01',
  advertisedName: 'SmartGlove-01',
  rssi: -55,
  isConnectable: true,
);

/// A peripheral that advertises no name at all — must show as
/// "Unknown Device" rather than being given an invented one.
const _unnamed = BleDiscoveredDevice(
  id: 'AA:BB:CC:DD:EE:02',
  advertisedName: '',
  rssi: -88,
  isConnectable: true,
);

class _FakeRegistrationRepository implements DeviceRegistrationRepository {
  _FakeRegistrationRepository({this.shouldFail = false});

  final bool shouldFail;
  var calls = 0;
  String? lastDeviceName;
  DeviceType? lastDeviceType;

  @override
  Future<RegisteredDevice> registerDevice({
    required String deviceName,
    required DeviceType deviceType,
  }) async {
    calls++;
    lastDeviceName = deviceName;
    lastDeviceType = deviceType;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (shouldFail) {
      throw const ApiException(message: 'The server had a problem. Please try again shortly.');
    }
    return RegisteredDevice(id: 'srv-1', deviceName: deviceName, deviceType: deviceType, isActive: true);
  }
}

/// Registration invalidates `devicesProvider` so a newly paired device
/// shows up in the list — this resolves instantly, unlike the real mock's
/// 300ms `Future.delayed`, which would otherwise leave a pending Timer
/// once these tests dispose their widget tree before it fires.
class _InstantDeviceRepository implements DeviceRepository {
  _InstantDeviceRepository({this.devices = const []});

  final List<DeviceDetail> devices;

  @override
  Future<void> unpairDevice(String id) async {}

  @override
  Future<List<DeviceDetail>> getDevices() async => devices;
}

DeviceDetail _registeredDetail({required String name, required DeviceType type, String id = 'srv-existing'}) =>
    DeviceDetail(
      id: id,
      name: name,
      type: type,
      isOnline: false,
      batteryPercent: 0,
      batteryHoursRemaining: 0,
      signalStrength: 0,
      firmwareVersion: 'v1',
      updateAvailable: false,
      sensors: const SensorReading(accelG: 0, gyroDps: 0, heartRateBpm: 0),
    );

Widget _harness({
  required FakeBleService ble,
  DeviceRegistrationRepository? registration,
  DeviceRepository? deviceRepository,
  Brightness brightness = Brightness.dark,
}) {
  return ProviderScope(
    overrides: [
      bleServiceProvider.overrideWithValue(ble),
      deviceRegistrationRepositoryProvider.overrideWithValue(registration ?? _FakeRegistrationRepository()),
      deviceRepositoryProvider.overrideWithValue(deviceRepository ?? _InstantDeviceRepository()),
    ],
    child: MaterialApp(
    // Mirrors main.dart's shell so screens render over the same ambient
    // field users see; the scaffold background is transparent by design.
    builder: (context, child) =>
        SaAmbientBackground(child: child ?? const SizedBox.shrink()),
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: const BlePairingSheetContent(),
        ),
      ),
    ),
  );
}

/// The radar pulse and the progress spinner loop forever, so
/// `pumpAndSettle` would never converge — every test here uses bounded
/// pumps instead, the same way `device_management_screen_test.dart` does.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Drives the flow to a real "Connected" state.
Future<void> _connect(WidgetTester tester, FakeBleService ble) async {
  ble.emitDevices(const [_named]);
  await _settle(tester);
  await tester.tap(find.text('Connect'));
  await _settle(tester);
}

void main() {
  group('BlePairingSheetContent', () {
    late FakeBleService ble;

    setUp(() => ble = FakeBleService());
    tearDown(() => ble.dispose());

    testWidgets('a platform-channel throw during the support check surfaces, not hangs', (tester) async {
      // Regression: startScan only caught BleFailure, so a
      // MissingPluginException from isSupported()/permissions/adapter probe
      // escaped the controller entirely. The sheet sat on "Scanning…"
      // forever with nothing to explain it — "connecting devices doesn't
      // work", with no error to go on.
      ble.supportCheckError = MissingPluginException('No implementation found');

      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Scanning for nearby devices…'), findsNothing);
      expect(find.textContaining('not available on this platform'), findsOneWidget);
    });

    testWidgets('an unexpected scan failure names itself', (tester) async {
      ble.supportCheckError = StateError('radio busy');

      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);

      // The raw text is kept rather than swallowed by "something went
      // wrong": a bug report needs it and it is not sensitive.
      expect(find.textContaining('radio busy'), findsOneWidget);
    });

    testWidgets('a non-BleFailure throw while connecting surfaces too', (tester) async {
      ble.connectFailure = MissingPluginException('No implementation found');

      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);
      ble.emitDevices(const [_named]);
      await _settle(tester);
      await tester.tap(find.text('Connect'));
      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('not available on this platform'), findsOneWidget);
    });

    testWidgets('renders_without_exception and starts a real scan', (tester) async {
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Pair a Device'), findsOneWidget);
      expect(find.text('Scanning for nearby devices…'), findsOneWidget);
      expect(ble.startScanCalls, 1);
    });

    testWidgets('devices appear live as each advertisement arrives', (tester) async {
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);

      expect(find.text('SmartGlove-01'), findsNothing);

      ble.emitDevices(const [_named]);
      await _settle(tester);
      expect(find.text('SmartGlove-01'), findsOneWidget);
      expect(find.text('Signal: Strong · -55 dBm · Available'), findsOneWidget);
      expect(find.text('Scanning — found 1 so far'), findsOneWidget);

      // A second device shows up mid-scan without waiting for the timeout.
      ble.emitDevices(const [_named, _unnamed]);
      await _settle(tester);
      expect(find.text('SmartGlove-01'), findsOneWidget);
      expect(find.text('Unknown Device'), findsOneWidget);
      expect(find.text('Scanning — found 2 so far'), findsOneWidget);
    });

    testWidgets('an unnamed peripheral is labelled Unknown Device, never invented', (tester) async {
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);

      ble.emitDevices(const [_unnamed]);
      await _settle(tester);

      expect(find.text('Unknown Device'), findsOneWidget);
      expect(find.text('Signal: Weak · -88 dBm · Available'), findsOneWidget);
    });

    testWidgets('renders_empty_state when the scan finds nothing', (tester) async {
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);

      ble.completeScan();
      await _settle(tester);

      expect(find.text('No devices found nearby.'), findsOneWidget);
      expect(find.text('Scan Again'), findsOneWidget);
    });

    testWidgets('rescanning restarts a real scan', (tester) async {
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);
      ble.completeScan();
      await _settle(tester);

      await tester.tap(find.text('Scan Again'));
      await _settle(tester);

      expect(ble.startScanCalls, 2);
      expect(find.text('Scanning for nearby devices…'), findsOneWidget);
    });

    testWidgets('permission denied shows Permission Required, not a silent failure', (tester) async {
      ble = FakeBleService(permission: BlePermissionStatus.denied);
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);

      expect(find.text('Permission Required'), findsOneWidget);
      expect(find.text('Grant Permission'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
      // Nothing was scanned for without permission.
      expect(ble.startScanCalls, 0);
    });

    testWidgets('permanently denied permission routes to app settings', (tester) async {
      ble = FakeBleService(permission: BlePermissionStatus.permanentlyDenied);
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);

      expect(find.text('Permission Required'), findsOneWidget);
      expect(find.text('Grant Permission'), findsNothing);

      await tester.tap(find.text('Open Settings'));
      await _settle(tester);
      expect(ble.openSettingsCalls, 1);
    });

    testWidgets('adapter off shows Bluetooth Disabled and can turn it on', (tester) async {
      ble = FakeBleService(adapter: BleAdapterStatus.off);
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);

      expect(find.text('Bluetooth Disabled'), findsOneWidget);
      expect(ble.startScanCalls, 0);

      await tester.tap(find.text('Turn On Bluetooth'));
      await _settle(tester);

      expect(find.text('Scanning for nearby devices…'), findsOneWidget);
      expect(ble.startScanCalls, 1);
    });

    testWidgets('iOS-style adapter (no programmatic enable) only instructs the user', (tester) async {
      ble = FakeBleService(adapter: BleAdapterStatus.off, canPromptToEnableBluetooth: false);
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);

      expect(find.text('Bluetooth Disabled'), findsOneWidget);
      expect(find.text('Turn On Bluetooth'), findsNothing);
      expect(find.textContaining('Control Centre'), findsOneWidget);
    });

    testWidgets('an unauthorized adapter is treated as a permission problem', (tester) async {
      ble = FakeBleService(adapter: BleAdapterStatus.unauthorized);
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);

      expect(find.text('Permission Required'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
    });

    testWidgets('hardware without BLE reports Bluetooth Unavailable', (tester) async {
      ble = FakeBleService(supported: false);
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);

      expect(find.text('Bluetooth Unavailable'), findsOneWidget);
      expect(ble.startScanCalls, 0);
    });

    testWidgets('connecting state is shown while the attempt is in flight', (tester) async {
      ble = FakeBleService()..connectGate = Completer<void>();
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);
      ble.emitDevices(const [_named]);
      await _settle(tester);

      await tester.tap(find.text('Connect'));
      await _settle(tester);

      expect(find.text('Connecting'), findsOneWidget);
      expect(find.text('Connecting to SmartGlove-01…'), findsOneWidget);

      ble.connectGate!.complete();
      await _settle(tester);
      expect(find.text('Connected'), findsOneWidget);
    });

    testWidgets('a real connection reports its discovered GATT services', (tester) async {
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);
      await _connect(tester, ble);

      expect(ble.connectCalls, 1);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('SmartGlove-01'), findsOneWidget);
      expect(find.text('2 GATT services discovered'), findsOneWidget);
      expect(find.text('What kind of device is this?'), findsOneWidget);
    });

    testWidgets('a failed connection surfaces the platform error verbatim', (tester) async {
      ble = FakeBleService()..connectFailure = const BleFailure('GATT error 133', code: 133);
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);
      await _connect(tester, ble);

      expect(find.text('Connection Failed'), findsOneWidget);
      expect(find.text('GATT error 133'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('retrying a failed connection reconnects to the same device', (tester) async {
      ble = FakeBleService()..connectFailure = const BleFailure('Device out of range');
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);
      await _connect(tester, ble);
      expect(find.text('Connection Failed'), findsOneWidget);

      ble.connectFailure = null;
      await tester.tap(find.text('Try Again'));
      await _settle(tester);

      expect(find.text('Connected'), findsOneWidget);
      expect(ble.connectCalls, 2);
    });

    testWidgets('registering sends the real advertised name and the chosen type', (tester) async {
      final registration = _FakeRegistrationRepository();
      await tester.pumpWidget(_harness(ble: ble, registration: registration));
      await _settle(tester);
      await _connect(tester, ble);

      await tester.tap(find.text('Glasses'));
      await _settle(tester);
      await tester.tap(find.text('Register Device'));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 100));

      expect(registration.calls, 1);
      expect(registration.lastDeviceName, 'SmartGlove-01');
      expect(registration.lastDeviceType, DeviceType.glasses);
      expect(find.text('Device Registered'), findsOneWidget);
      expect(find.text('Registered as Glasses.'), findsOneWidget);
    });

    testWidgets(
      'the glove-only motion display never appears while pairing a non-glove device (e.g. glasses)',
      (tester) async {
        await tester.pumpWidget(_harness(ble: ble));
        await _settle(tester);
        await _connect(tester, ble);

        await tester.tap(find.text('Glasses'));
        await _settle(tester);

        expect(find.textContaining('Motion:'), findsNothing);
        expect(find.textContaining('Motion Risk:'), findsNothing);

        await tester.tap(find.text('Register Device'));
        await _settle(tester);
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Device Registered'), findsOneWidget);
        expect(find.textContaining('Motion:'), findsNothing);
        expect(find.textContaining('Motion Risk:'), findsNothing);
      },
    );

    testWidgets('the glove motion display appears for the default Glove selection', (tester) async {
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);
      await _connect(tester, ble);

      // No tap on the type picker: the default selection is already Glove.
      expect(find.textContaining('Motion Risk:'), findsOneWidget);
    });

    testWidgets(
      'reconnecting the same physical device reuses the existing registered device, not a duplicate',
      (tester) async {
        final registration = _FakeRegistrationRepository();
        final existing = _registeredDetail(name: 'SmartGlove-01', type: DeviceType.glasses, id: 'srv-existing');
        await tester.pumpWidget(
          _harness(
            ble: ble,
            registration: registration,
            deviceRepository: _InstantDeviceRepository(devices: [existing]),
          ),
        );
        await _settle(tester);
        await _connect(tester, ble);

        await tester.tap(find.text('Glasses'));
        await _settle(tester);
        await tester.tap(find.text('Register Device'));
        await _settle(tester);
        await tester.pump(const Duration(milliseconds: 100));

        // No new backend record: the already-registered device (matched by
        // its fixed advertised name + the chosen type) was reused as-is.
        expect(registration.calls, 0);
        expect(find.text('Device Registered'), findsOneWidget);
      },
    );

    testWidgets('a different device name still registers as a new device', (tester) async {
      final registration = _FakeRegistrationRepository();
      final existing = _registeredDetail(name: 'SomeOtherWearable', type: DeviceType.glasses, id: 'srv-other');
      await tester.pumpWidget(
        _harness(
          ble: ble,
          registration: registration,
          deviceRepository: _InstantDeviceRepository(devices: [existing]),
        ),
      );
      await _settle(tester);
      await _connect(tester, ble);

      await tester.tap(find.text('Glasses'));
      await _settle(tester);
      await tester.tap(find.text('Register Device'));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 100));

      // A different physical device (different name) is registered
      // normally rather than being folded into the unrelated existing one.
      expect(registration.calls, 1);
      expect(registration.lastDeviceName, 'SmartGlove-01');
      expect(find.text('Device Registered'), findsOneWidget);
    });

    testWidgets('a backend failure keeps the live connection and shows the error', (tester) async {
      final registration = _FakeRegistrationRepository(shouldFail: true);
      await tester.pumpWidget(_harness(ble: ble, registration: registration));
      await _settle(tester);
      await _connect(tester, ble);

      await tester.tap(find.text('Register Device'));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Device Registered'), findsNothing);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.textContaining('The server had a problem'), findsOneWidget);
    });

    testWidgets('an unnamed device registers under a name that still identifies it', (tester) async {
      final registration = _FakeRegistrationRepository();
      await tester.pumpWidget(_harness(ble: ble, registration: registration));
      await _settle(tester);
      ble.emitDevices(const [_unnamed]);
      await _settle(tester);
      await tester.tap(find.text('Connect'));
      await _settle(tester);
      await tester.tap(find.text('Register Device'));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 100));

      expect(registration.lastDeviceName, 'Unknown Device (AA:BB:CC:DD:EE:02)');
    });

    testWidgets('a real drop shows Disconnected, then reconnects automatically', (tester) async {
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);
      await _connect(tester, ble);
      expect(find.text('Connected'), findsOneWidget);

      ble.dropConnection(_named.id);
      await _settle(tester);
      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.textContaining('went out of range or powered off'), findsOneWidget);

      // The bounded backoff elapses and the retry succeeds.
      await tester.pump(BlePairingController.reconnectBackoff);
      await _settle(tester);
      expect(find.text('Connected'), findsOneWidget);
      expect(ble.connectCalls, 2);
    });

    testWidgets('reconnection gives up after a bounded number of attempts', (tester) async {
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);
      await _connect(tester, ble);

      ble.connectFailure = const BleFailure('Device out of range');
      ble.dropConnection(_named.id);
      await _settle(tester);

      for (var attempt = 0; attempt < BlePairingController.maxReconnectAttempts; attempt++) {
        await tester.pump(BlePairingController.reconnectBackoff);
        await _settle(tester);
      }

      expect(find.text('Connection Failed'), findsOneWidget);
      expect(find.textContaining('could not reconnect'), findsOneWidget);
      // 1 initial + exactly maxReconnectAttempts retries, never an endless loop.
      expect(ble.connectCalls, 1 + BlePairingController.maxReconnectAttempts);
    });

    testWidgets('manual disconnect really disconnects and returns to scanning', (tester) async {
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);
      await _connect(tester, ble);

      await tester.tap(find.text('Disconnect'));
      await _settle(tester);

      expect(ble.disconnectCalls, 1);
      expect(find.text('Connected'), findsNothing);
      expect(find.text('Scan Again'), findsOneWidget);
    });

    testWidgets('bluetooth switching off mid-scan interrupts it', (tester) async {
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);
      ble.emitDevices(const [_named]);
      await _settle(tester);

      ble.emitAdapterStatus(BleAdapterStatus.off);
      await _settle(tester);

      expect(find.text('Bluetooth Disabled'), findsOneWidget);
      expect(find.text('SmartGlove-01'), findsNothing);
    });

    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(_harness(ble: ble, brightness: Brightness.light));
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(_harness(ble: ble));
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('honours reduced motion by not looping the radar', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bleServiceProvider.overrideWithValue(ble),
            deviceRegistrationRepositoryProvider.overrideWithValue(_FakeRegistrationRepository()),
          ],
          child: MaterialApp(
    // Mirrors main.dart's shell so screens render over the same ambient
    // field users see; the scaffold background is transparent by design.
    builder: (context, child) =>
        SaAmbientBackground(child: child ?? const SizedBox.shrink()),
            theme: AppTheme.dark,
            home: const MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: Scaffold(body: SingleChildScrollView(child: BlePairingSheetContent())),
            ),
          ),
        ),
      );
      await _settle(tester);

      expect(tester.takeException(), isNull);
      // No repeating ticker means no perpetually-scheduled frames.
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('BlePairingSheetContent goldens', () {
    Future<void> goldenFor(
      WidgetTester tester,
      String name, {
      required FakeBleService ble,
      required Brightness brightness,
      Future<void> Function(WidgetTester tester, FakeBleService ble)? arrange,
    }) async {
      await tester.pumpWidgetBuilder(
        _harness(ble: ble, brightness: brightness),
        surfaceSize: const Size(390, 844),
      );
      await _settle(tester);
      if (arrange != null) await arrange(tester, ble);
      await screenMatchesGolden(
        tester,
        name,
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    }

    for (final brightness in Brightness.values) {
      final suffix = brightness == Brightness.dark ? 'dark' : 'light';

      testGoldens('golden - scanning ($suffix)', (tester) async {
        final ble = FakeBleService();
        addTearDown(ble.dispose);
        await goldenFor(tester, 'ble_pairing_sheet_scanning_$suffix', ble: ble, brightness: brightness);
      });

      testGoldens('golden - found devices ($suffix)', (tester) async {
        final ble = FakeBleService();
        addTearDown(ble.dispose);
        await goldenFor(
          tester,
          'ble_pairing_sheet_found_devices_$suffix',
          ble: ble,
          brightness: brightness,
          arrange: (tester, ble) async {
            ble.emitDevices(const [_named, _unnamed]);
            await _settle(tester);
            ble.completeScan();
            await _settle(tester);
          },
        );
      });

      testGoldens('golden - connecting ($suffix)', (tester) async {
        final ble = FakeBleService()..connectGate = Completer<void>();
        addTearDown(ble.dispose);
        await goldenFor(
          tester,
          'ble_pairing_sheet_connecting_$suffix',
          ble: ble,
          brightness: brightness,
          arrange: (tester, ble) async {
            ble.emitDevices(const [_named]);
            await _settle(tester);
            await tester.tap(find.text('Connect'));
            await _settle(tester);
          },
        );
      });

      testGoldens('golden - connected ($suffix)', (tester) async {
        final ble = FakeBleService();
        addTearDown(ble.dispose);
        await goldenFor(
          tester,
          'ble_pairing_sheet_connected_$suffix',
          ble: ble,
          brightness: brightness,
          arrange: (tester, ble) async => _connect(tester, ble),
        );
      });

      testGoldens('golden - connection failed ($suffix)', (tester) async {
        final ble = FakeBleService()..connectFailure = const BleFailure('GATT error 133', code: 133);
        addTearDown(ble.dispose);
        await goldenFor(
          tester,
          'ble_pairing_sheet_connection_failed_$suffix',
          ble: ble,
          brightness: brightness,
          arrange: (tester, ble) async => _connect(tester, ble),
        );
      });

      testGoldens('golden - disconnected ($suffix)', (tester) async {
        final ble = FakeBleService();
        addTearDown(ble.dispose);
        await goldenFor(
          tester,
          'ble_pairing_sheet_disconnected_$suffix',
          ble: ble,
          brightness: brightness,
          arrange: (tester, ble) async {
            await _connect(tester, ble);
            ble.connectFailure = const BleFailure('Device out of range');
            ble.dropConnection(_named.id);
            await _settle(tester);
          },
        );
      });

      testGoldens('golden - bluetooth disabled ($suffix)', (tester) async {
        final ble = FakeBleService(adapter: BleAdapterStatus.off);
        addTearDown(ble.dispose);
        await goldenFor(
          tester,
          'ble_pairing_sheet_bluetooth_disabled_$suffix',
          ble: ble,
          brightness: brightness,
        );
      });

      testGoldens('golden - permission required ($suffix)', (tester) async {
        final ble = FakeBleService(permission: BlePermissionStatus.denied);
        addTearDown(ble.dispose);
        await goldenFor(
          tester,
          'ble_pairing_sheet_permission_required_$suffix',
          ble: ble,
          brightness: brightness,
        );
      });
    }
  });
}
