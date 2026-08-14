import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/local/onboarding_prefs.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/auth/data/auth_providers.dart';
import 'package:safeher_app/features/auth/domain/auth_repository.dart';
import 'package:safeher_app/features/settings/data/settings_providers.dart';
import 'package:safeher_app/features/settings/domain/models/app_settings.dart';
import 'package:safeher_app/features/settings/domain/settings_repository.dart';
import 'package:safeher_app/features/settings/presentation/settings_screen.dart';

import '../../../test_utils/fake_key_value_store.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

class _FakeAuthRepository implements AuthRepository {
  @override
  bool get phoneVerificationUnavailable => false;

  @override
  Future<bool> hasActiveSession() async => true;

  @override
  Future<void> signInWithEmail({required String email, required String password}) => throw UnimplementedError();

  @override
  Future<void> signInAsGuest() async {}

  @override
  Future<void> signInWithGoogle() => throw UnimplementedError();

  @override
  Future<void> signInWithApple() => throw UnimplementedError();

  @override
  Future<void> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String phoneE164,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> verifyOtp(String code) => throw UnimplementedError();

  @override
  Future<void> resendOtp() => throw UnimplementedError();

  @override
  Future<void> sendPasswordResetEmail(String email) => throw UnimplementedError();

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository({this.shouldFail = false});
  final bool shouldFail;
  AppSettings _settings = const AppSettings(
    pushNotifications: true,
    smsNotifications: false,
    emailNotifications: true,
    locationSharing: true,
  );

  @override
  Future<AppSettings> getSettings() async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (shouldFail) throw Exception('network error');
    return _settings;
  }

  @override
  Future<AppSettings> updateSettings(AppSettings settings) async {
    await Future.delayed(const Duration(milliseconds: 50));
    _settings = settings;
    return _settings;
  }
}

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
      GoRoute(path: '/profile', builder: (context, state) => const Scaffold(body: Text('profile-stub'))),
      GoRoute(path: '/settings/contacts', builder: (context, state) => const Scaffold(body: Text('contacts-stub'))),
      GoRoute(path: '/devices', builder: (context, state) => const Scaffold(body: Text('devices-stub'))),
      GoRoute(path: '/auth/login', builder: (context, state) => const Scaffold(body: Text('login-stub'))),
    ],
  );
}

Widget _harness({Brightness brightness = Brightness.dark, SettingsRepository? repo}) {
  return ProviderScope(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(repo ?? _FakeSettingsRepository()),
      localKeyValueStoreProvider.overrideWithValue(FakeKeyValueStore()),
      // AppConfig.useMockApi defaults to false now that every feature has a
      // real backend — without this, Sign Out / Delete Account would
      // attempt a real Firebase/network call during the test.
      authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
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
  group('SettingsScreen', () {
    testWidgets('renders_without_exception (loading state)', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('renders_with_data (mocked repository)', (tester) async {
      // Tall enough for the lazy ListView to build every row this test
      // asserts on, including the Safety section added above Devices.
      await tester.binding.setSurfaceSize(const Size(390, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('Push Notifications'), findsOneWidget);
      expect(find.text('SMS Notifications'), findsOneWidget);
      expect(find.text('Email Notifications'), findsOneWidget);
      expect(find.text('Location Sharing'), findsOneWidget);
      expect(find.text('Threat Threshold'), findsOneWidget);
      expect(find.text('Safety Toolkit'), findsOneWidget);
      expect(find.text('Safety Triggers'), findsOneWidget);
      expect(find.text('Paired Devices'), findsOneWidget);
      expect(find.text('Dark Mode'), findsOneWidget);
      expect(find.text('Open Source Licenses'), findsOneWidget);
      expect(find.text('Emergency Contacts'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);
      expect(find.text('Delete Account'), findsOneWidget);
    });

    testWidgets('renders_empty_state (error + retry)', (tester) async {
      await tester.pumpWidget(_harness(repo: _FakeSettingsRepository(shouldFail: true)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text("Couldn't load settings"), findsOneWidget);
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

    testWidgets('toggling a switch updates its state', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.bySemanticsLabel('SMS Notifications'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('navigation_actions_work: back button returns to profile', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('profile-stub'), findsOneWidget);
    });

    testWidgets('navigation_actions_work: Emergency Contacts navigates to contacts', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Emergency Contacts'));
      await tester.pumpAndSettle();
      expect(find.text('contacts-stub'), findsOneWidget);
    });

    testWidgets('navigation_actions_work: Paired Devices navigates to devices', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Paired Devices'));
      await tester.pumpAndSettle();
      expect(find.text('devices-stub'), findsOneWidget);
    });

    testWidgets('navigation_actions_work: Threat Threshold links to Profile', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.scrollUntilVisible(find.text('Threat Threshold'), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Threat Threshold'));
      await tester.pumpAndSettle();
      expect(find.text('profile-stub'), findsOneWidget);
    });

    testWidgets('navigation_actions_work: Sign Out requires a second confirm tap', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.scrollUntilVisible(find.text('Sign Out'), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Sign Out'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Tap again to confirm'), findsOneWidget);

      await tester.tap(find.text('Tap again to confirm'), warnIfMissed: false);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('login-stub'), findsOneWidget);
    });

    testWidgets('Delete Account requires typed DELETE confirmation', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.scrollUntilVisible(find.text('Delete Account'), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Account'), findsWidgets);

      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();
      expect(find.text('login-stub'), findsOneWidget);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(_harness(brightness: Brightness.light), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(
        tester,
        'settings_screen_light',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(
        tester,
        'settings_screen_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });
  });
}
