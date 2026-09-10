import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/safety/data/safety_providers.dart';
import 'package:safeher_app/features/safety/domain/models/safety_settings.dart';
import 'package:safeher_app/features/safety/presentation/safety_pin_screen.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

import '../../../test_utils/fake_safety_repository.dart';

/// Golden coverage for the safety-PIN screen -- the PIN that must be entered
/// to cancel a triggered alert. Two states worth capturing: no PIN set yet
/// (the create flow) and a PIN already set (the change/remove flow).
Widget _harness({
  Brightness brightness = Brightness.dark,
  bool pinSet = false,
}) {
  final router = GoRouter(
    initialLocation: '/settings/safety/pin',
    routes: [
      GoRoute(path: '/settings/safety/pin', builder: (_, __) => const SafetyPinScreen()),
      GoRoute(path: '/home', builder: (_, __) => const Scaffold(body: Text('home'))),
    ],
  );
  return ProviderScope(
    overrides: [
      safetyRepositoryProvider.overrideWithValue(
        FakeSafetyRepository(pinStatus: SafetyPinStatus(isSet: pinSet)),
      ),
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
  group('SafetyPinScreen', () {
    testWidgets('renders without exception', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testGoldens('golden - no PIN set, light', (tester) async {
      await tester.pumpWidgetBuilder(
        _harness(brightness: Brightness.light),
        surfaceSize: const Size(390, 844),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await screenMatchesGolden(tester, 'safety_pin_screen_light',
          customPump: (t) async => t.pump(const Duration(milliseconds: 300)));
    });

    testGoldens('golden - no PIN set, dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 300));
      await screenMatchesGolden(tester, 'safety_pin_screen_dark',
          customPump: (t) async => t.pump(const Duration(milliseconds: 300)));
    });

    testGoldens('golden - PIN already set, dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(pinSet: true), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 300));
      await screenMatchesGolden(tester, 'safety_pin_screen_set_dark',
          customPump: (t) async => t.pump(const Duration(milliseconds: 300)));
    });
  });
}
