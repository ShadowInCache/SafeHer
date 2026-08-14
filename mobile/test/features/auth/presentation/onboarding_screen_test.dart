import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/local/local_key_value_store.dart';
import 'package:safeher_app/core/local/onboarding_prefs.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/auth/presentation/onboarding_screen.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

class _FakeKeyValueStore implements LocalKeyValueStore {
  bool hasSeenOnboarding = false;

  @override
  bool getBool(String key, {bool defaultValue = false}) => hasSeenOnboarding;

  @override
  Future<void> setBool(String key, bool value) async => hasSeenOnboarding = value;

  @override
  double getDouble(String key, {double defaultValue = 0}) => defaultValue;

  @override
  Future<void> setDouble(String key, double value) async {}

  @override
  int getInt(String key, {int defaultValue = 0}) => defaultValue;

  @override
  Future<void> setInt(String key, int value) async {}
}

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/onboarding',
    routes: [
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/auth/login', builder: (context, state) => const Scaffold(body: Text('login-stub'))),
    ],
  );
}

Widget _harness({Brightness brightness = Brightness.dark, _FakeKeyValueStore? store}) {
  return ProviderScope(
    overrides: [
      localKeyValueStoreProvider.overrideWithValue(store ?? _FakeKeyValueStore()),
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

/// Drags the PageView a full page-width to the left from a fixed anchor
/// point, then pumps in small bounded steps until the snap animation
/// settles. Deliberately avoids tester.fling() (velocity-based, and
/// BouncingScrollPhysics can leave residual velocity that never reaches
/// pumpAndSettle's zero threshold) and avoids anchoring on a specific text
/// widget (its position can shift between frames as parallax recalculates).
Future<void> _swipeToNextPage(WidgetTester tester, Size surfaceSize) async {
  final start = Offset(surfaceSize.width * 0.8, surfaceSize.height * 0.4);
  await tester.dragFrom(start, Offset(-surfaceSize.width, 0));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  group('OnboardingScreen', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(_harness(brightness: Brightness.light));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Always Protected'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Always Protected'), findsOneWidget);
    });

    testWidgets('handles tap on Skip and persists onboarding flag', (tester) async {
      final store = _FakeKeyValueStore();
      await tester.pumpWidget(_harness(store: store));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(store.hasSeenOnboarding, isTrue);
      expect(find.text('login-stub'), findsOneWidget);
    });

    testWidgets('Skip is hidden on the last page', (tester) async {
      const surfaceSize = Size(390, 844);
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      await _swipeToNextPage(tester, surfaceSize);
      await _swipeToNextPage(tester, surfaceSize);

      expect(find.text('Help in Seconds'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
      expect(find.text('Get Started'), findsOneWidget);
    });

    testWidgets('navigation_actions_work: Get Started persists flag and navigates', (tester) async {
      const surfaceSize = Size(390, 844);
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = _FakeKeyValueStore();
      await tester.pumpWidget(_harness(store: store));
      await tester.pumpAndSettle();

      await _swipeToNextPage(tester, surfaceSize);
      await _swipeToNextPage(tester, surfaceSize);

      await tester.tap(find.text('Get Started'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(store.hasSeenOnboarding, isTrue);
      expect(find.text('login-stub'), findsOneWidget);
    });

    testGoldens('golden - light page 1', (tester) async {
      await tester.pumpWidgetBuilder(
        _harness(brightness: Brightness.light),
        surfaceSize: const Size(390, 844),
      );
      await tester.pumpAndSettle();
      await screenMatchesGolden(tester, 'onboarding_screen_light');
    });

    testGoldens('golden - dark page 1', (tester) async {
      await tester.pumpWidgetBuilder(
        _harness(),
        surfaceSize: const Size(390, 844),
      );
      await tester.pumpAndSettle();
      // The ripple painter on page 3 loops, but page 1 has no looping
      // animation so pumpAndSettle already converges here.
      await screenMatchesGolden(tester, 'onboarding_screen_dark');
    });
  });
}
