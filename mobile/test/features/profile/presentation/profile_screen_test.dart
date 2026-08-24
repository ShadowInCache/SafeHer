import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/navigation/sa_bottom_nav_bar.dart';
import 'package:safeher_app/core/local/onboarding_prefs.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/auth/data/auth_providers.dart';
import 'package:safeher_app/features/contacts/data/contacts_providers.dart';
import 'package:safeher_app/features/contacts/domain/contacts_repository.dart';
import 'package:safeher_app/features/contacts/domain/models/alert_channels.dart';
import 'package:safeher_app/features/contacts/domain/models/contact.dart';
import 'package:safeher_app/features/devices/data/device_providers.dart';
import 'package:safeher_app/features/devices/domain/device_repository.dart';
import 'package:safeher_app/features/devices/domain/models/device_detail.dart';
import 'package:safeher_app/features/profile/data/profile_providers.dart';
import 'package:safeher_app/features/profile/domain/models/user_profile.dart';
import 'package:safeher_app/features/profile/domain/profile_repository.dart';
import 'package:safeher_app/features/profile/presentation/profile_screen.dart';

import '../../../test_utils/fake_auth_repository.dart';
import '../../../test_utils/fake_key_value_store.dart';
import '../../../test_utils/offline_test_overrides.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

UserProfile _sampleProfile() => const UserProfile(
  name: 'Priya Patel',
  email: 'priya.patel@example.com',
  phone: '+1 (555) 123-4567',
  memberSince: 'March 2025',
  safetyScore: 87,
  streakDays: 12,
);

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository({this.shouldFail = false});
  final bool shouldFail;

  @override
  Future<UserProfile> getUserProfile() async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (shouldFail) throw Exception('network error');
    return _sampleProfile();
  }

  @override
  Future<UserProfile> updateProfile({String? name, String? phone, double? threatThreshold}) => throw UnimplementedError();

  @override
  Future<List<int>> exportMyData() async => utf8.encode('{"account":{}}');
}

class _FakeContactsRepository implements ContactsRepository {
  var verificationSends = <String>[];
  var verificationCodes = <String>[];

  /// Set to make [confirmVerificationCode] throw, as a wrong code does.
  bool verificationFails = false;

  @override
  Future<bool> sendVerificationCode(String id) async {
    verificationSends.add(id);
    return false;
  }

  @override
  Future<List<Contact>> confirmVerificationCode(String id, String code) async {
    verificationCodes.add(code);
    if (verificationFails) throw Exception('wrong code');
    return getContacts();
  }

  /// Defaults to "everything works" so existing tests are unaffected by the
  /// unreachable-contact warning; the settings tests override it.
  AlertChannels channels = const AlertChannels(sms: true, email: true, push: true);

  @override
  Future<AlertChannels> getAlertChannels() async => channels;

  @override
  Future<List<Contact>> updateContact(
    String id, {
    String? name,
    String? phone,
    String? relationship,
    String? email,
  }) async => getContacts();

  @override
  Future<List<Contact>> getContacts() async {
    // _ProfileContent (and this provider) only mounts once the profile
    // future above resolves, so this delay is additive with that one —
    // kept short so the combined wait stays well inside this test file's
    // pump budgets.
    await Future.delayed(const Duration(milliseconds: 10));
    return const [
      Contact(id: '1', name: 'Anika Sharma', phone: '+15550101000', relationship: 'Sister', priority: 1, confirmed: true),
      Contact(id: '2', name: 'Rahul Verma', phone: '+15550101000', relationship: 'Partner', priority: 2, confirmed: true),
    ];
  }

  @override
  Future<List<Contact>> addContact(
    String name,
    String phone,
    String relationship, {
    String? email,
  }) => throw UnimplementedError();

  @override
  Future<List<Contact>> removeContact(String id) => throw UnimplementedError();

  @override
  Future<List<Contact>> reorderContacts(List<Contact> newOrder) => throw UnimplementedError();
}

class _FakeDeviceRepository implements DeviceRepository {
  @override
  Future<void> unpairDevice(String id) async {}

  @override
  Future<List<DeviceDetail>> getDevices() async {
    // Same staggered-mount reasoning as _FakeContactsRepository above.
    await Future.delayed(const Duration(milliseconds: 10));
    return const [
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
    ];
  }
}

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
      GoRoute(path: '/home', builder: (context, state) => const Scaffold(body: Text('home-stub'))),
      GoRoute(path: '/monitor', builder: (context, state) => const Scaffold(body: Text('monitor-stub'))),
      GoRoute(path: '/devices', builder: (context, state) => const Scaffold(body: Text('devices-stub'))),
      GoRoute(path: '/emergency', builder: (context, state) => const Scaffold(body: Text('emergency-stub'))),
      GoRoute(path: '/settings', builder: (context, state) => const Scaffold(body: Text('settings-stub'))),
      GoRoute(
        path: '/settings/contacts',
        builder: (context, state) => const Scaffold(body: Text('settings-contacts-stub')),
      ),
      GoRoute(path: '/auth/login', builder: (context, state) => const Scaffold(body: Text('login-stub'))),
      GoRoute(path: '/onboarding', builder: (context, state) => const Scaffold(body: Text('onboarding-stub'))),
    ],
  );
}

Widget _harness({Brightness brightness = Brightness.dark, ProfileRepository? repo, FakeKeyValueStore? store}) {
  return ProviderScope(
    overrides: [
      profileRepositoryProvider.overrideWithValue(repo ?? _FakeProfileRepository()),
      contactsRepositoryProvider.overrideWithValue(_FakeContactsRepository()),
      deviceRepositoryProvider.overrideWithValue(_FakeDeviceRepository()),
      localKeyValueStoreProvider.overrideWithValue(store ?? FakeKeyValueStore()),
      // Sign Out / Delete Account would otherwise reach the real
      // Firebase-backed repository, which has no platform channel here.
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      ...offlineTestOverrides(),
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
  group('ProfileScreen', () {
    testWidgets('renders_without_exception (loading state)', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('renders_with_data (mocked repository)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('Priya Patel'), findsOneWidget);
      expect(find.text('priya.patel@example.com'), findsOneWidget);
      expect(find.text('87'), findsOneWidget);
      expect(find.text('Anika Sharma'), findsOneWidget);
      expect(find.text('Rahul Verma'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);
    });

    testWidgets('renders_empty_state (error + retry)', (tester) async {
      await tester.pumpWidget(_harness(repo: _FakeProfileRepository(shouldFail: true)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text("Couldn't load your profile"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('the nav bar stays at the bottom while the profile is loading', (tester) async {
      // Regression: the shimmer is a SingleChildScrollView, which shrink-wraps
      // its content, and a Stack sizes to its largest non-positioned child --
      // so during loading the Stack was only as tall as the shimmer and the
      // nav bar's Positioned(bottom: 0) anchored halfway up the screen.
      const surfaceSize = Size(390, 844);
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_harness());
      await tester.pump(); // still loading: the fake repo takes 50ms

      expect(find.byType(SaBottomNavBar), findsOneWidget);
      final navBottom = tester.getRect(find.byType(SaBottomNavBar)).bottom;
      expect(
        navBottom,
        moreOrLessEquals(surfaceSize.height, epsilon: 0.5),
        reason: 'nav bar should sit on the bottom edge while loading, not float mid-screen',
      );

      // Let the profile resolve and the content's own device/contact fetches
      // finish, so nothing is left pending at teardown.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Replay Introduction clears the flag and returns to onboarding', (tester) async {
      // hasSeenOnboarding is set the first time Skip or Get Started is tapped
      // and was never cleared, so the introduction became unreachable without
      // wiping the app's data -- which also signs the user out.
      final store = FakeKeyValueStore();
      await store.setBool('hasSeenOnboarding', true);

      await tester.binding.setSurfaceSize(const Size(390, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_harness(store: store));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      final replay = find.text('Replay Introduction');
      await tester.scrollUntilVisible(replay, 300, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(replay);
      await tester.pump();
      await tester.tap(replay);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(store.getBool('hasSeenOnboarding'), isFalse);
      expect(find.text('onboarding-stub'), findsOneWidget);
    });

    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(_harness(brightness: Brightness.light));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('navigation_actions_work: Settings row navigates to settings', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.scrollUntilVisible(find.text('Settings'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('settings-stub'), findsOneWidget);
    });

    testWidgets('navigation_actions_work: Sign Out requires a second confirm tap', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.scrollUntilVisible(find.text('Sign Out'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Sign Out'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Tap again to confirm'), findsOneWidget);

      await tester.tap(find.text('Tap again to confirm'));
      await tester.pumpAndSettle();
      expect(find.text('login-stub'), findsOneWidget);
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
        'profile_screen_light',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(
        tester,
        'profile_screen_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });
  });
}
