import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/settings/data/settings_providers.dart';
import 'package:safeher_app/features/settings/domain/models/app_settings.dart';
import 'package:safeher_app/features/settings/domain/settings_repository.dart';
import 'package:safeher_app/features/settings/presentation/settings_screen.dart';

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository({this.shouldFail = false});
  final bool shouldFail;
  AppSettings _settings = const AppSettings(pushNotifications: true, locationSharing: true, biometricLock: false);

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
      GoRoute(path: '/auth/login', builder: (context, state) => const Scaffold(body: Text('login-stub'))),
    ],
  );
}

Widget _harness({Brightness brightness = Brightness.dark, SettingsRepository? repo}) {
  return ProviderScope(
    overrides: [settingsRepositoryProvider.overrideWithValue(repo ?? _FakeSettingsRepository())],
    child: MaterialApp.router(
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
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('Push Notifications'), findsOneWidget);
      expect(find.text('Location Sharing'), findsOneWidget);
      expect(find.text('Biometric Lock'), findsOneWidget);
      expect(find.text('Emergency Contacts'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);
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

      await tester.tap(find.bySemanticsLabel('Biometric Lock'));
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

    testWidgets('navigation_actions_work: Sign Out requires a second confirm tap', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Sign Out'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Tap again to confirm'), findsOneWidget);

      await tester.tap(find.text('Tap again to confirm'));
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
