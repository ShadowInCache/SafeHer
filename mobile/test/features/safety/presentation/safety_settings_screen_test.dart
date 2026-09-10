import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/safety/data/safety_providers.dart';
import 'package:safeher_app/features/safety/domain/models/safety_settings.dart';
import 'package:safeher_app/features/safety/presentation/safety_settings_screen.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

import '../../../test_utils/fake_auth_repository.dart';
import '../../../test_utils/fake_safety_repository.dart';
import 'package:safeher_app/features/auth/data/auth_providers.dart';

/// Golden coverage for the safety-triggers settings screen: shake trigger,
/// voice commands, PIN-to-cancel, journey auto-share. Driven by the same fake
/// safety repository the rest of the safety tests use.
Widget _harness({
  Brightness brightness = Brightness.dark,
  SafetyPreferences preferences = const SafetyPreferences.defaults(),
  SafetyPinStatus pinStatus = const SafetyPinStatus(isSet: false),
}) {
  final router = GoRouter(
    initialLocation: '/settings/safety',
    routes: [
      GoRoute(path: '/settings/safety', builder: (_, __) => const SafetySettingsScreen()),
      GoRoute(path: '/settings/safety/pin', builder: (_, __) => const Scaffold(body: Text('pin'))),
      GoRoute(path: '/home', builder: (_, __) => const Scaffold(body: Text('home'))),
    ],
  );
  return ProviderScope(
    overrides: [
      safetyRepositoryProvider.overrideWithValue(
        FakeSafetyRepository(preferences: preferences, pinStatus: pinStatus),
      ),
      // The preferences notifier gates on an active session before it fetches;
      // without this the screen sits in a loading shimmer that never settles.
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
    ],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      routerConfig: router,
      builder: (context, child) =>
          SaAmbientBackground(child: child ?? const SizedBox.shrink()),
    ),
  );
}

void main() {
  group('SafetySettingsScreen', () {
    testWidgets('renders without exception', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        _harness(brightness: Brightness.light),
        surfaceSize: const Size(390, 900),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await screenMatchesGolden(tester, 'safety_settings_screen_light',
          customPump: (t) async => t.pump(const Duration(milliseconds: 300)));
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 900));
      await tester.pump(const Duration(milliseconds: 300));
      await screenMatchesGolden(tester, 'safety_settings_screen_dark',
          customPump: (t) async => t.pump(const Duration(milliseconds: 300)));
    });
  });
}
