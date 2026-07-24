import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/local/local_key_value_store.dart';
import 'package:safeher_app/core/local/onboarding_prefs.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/auth/data/auth_providers.dart';
import 'package:safeher_app/features/auth/domain/auth_repository.dart';
import 'package:safeher_app/features/auth/presentation/splash_screen.dart';

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.hasSession = false});
  final bool hasSession;

  @override
  Future<bool> hasActiveSession() async => hasSession;

  @override
  Future<void> signInWithEmail({required String email, required String password}) async {}

  @override
  Future<void> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String phoneE164,
    required String password,
  }) async {}

  @override
  Future<void> verifyOtp(String code) async {}

  @override
  Future<void> resendOtp() async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {}
}

class _FakeKeyValueStore implements LocalKeyValueStore {
  _FakeKeyValueStore({this.hasSeenOnboarding = false});
  bool hasSeenOnboarding;

  @override
  bool getBool(String key, {bool defaultValue = false}) => hasSeenOnboarding;

  @override
  Future<void> setBool(String key, bool value) async => hasSeenOnboarding = value;
}

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (context, state) => const Scaffold(body: Text('onboarding-stub'))),
      GoRoute(path: '/auth/login', builder: (context, state) => const Scaffold(body: Text('login-stub'))),
      GoRoute(path: '/home', builder: (context, state) => const Scaffold(body: Text('home-stub'))),
    ],
  );
}

Widget _harness({
  required bool hasSeenOnboarding,
  required bool hasSession,
  Brightness brightness = Brightness.dark,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuthRepository(hasSession: hasSession)),
      localKeyValueStoreProvider.overrideWithValue(_FakeKeyValueStore(hasSeenOnboarding: hasSeenOnboarding)),
    ],
    child: MaterialApp.router(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      routerConfig: _buildTestRouter(),
    ),
  );
}

void main() {
  group('SplashScreen', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(_harness(hasSeenOnboarding: true, hasSession: true, brightness: Brightness.light));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('SAFEHER'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(_harness(hasSeenOnboarding: true, hasSession: true));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('SAFEHER'), findsOneWidget);
    });

    testWidgets('redirects to onboarding when not yet seen', (tester) async {
      await tester.pumpWidget(_harness(hasSeenOnboarding: false, hasSession: false));
      await tester.pump(const Duration(milliseconds: 1900));
      await tester.pumpAndSettle();
      expect(find.text('onboarding-stub'), findsOneWidget);
    });

    testWidgets('redirects to login when onboarding seen but no session', (tester) async {
      await tester.pumpWidget(_harness(hasSeenOnboarding: true, hasSession: false));
      await tester.pump(const Duration(milliseconds: 1900));
      await tester.pumpAndSettle();
      expect(find.text('login-stub'), findsOneWidget);
    });

    testWidgets('redirects to home when onboarding seen and session active', (tester) async {
      await tester.pumpWidget(_harness(hasSeenOnboarding: true, hasSession: true));
      await tester.pump(const Duration(milliseconds: 1900));
      await tester.pumpAndSettle();
      expect(find.text('home-stub'), findsOneWidget);
    });

    testWidgets('completes almost immediately under reduced motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      await tester.pumpWidget(_harness(hasSeenOnboarding: true, hasSession: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('home-stub'), findsOneWidget);
    });

    testGoldens('golden - light', (tester) async {
      // Capture mid-animation, well before the ~1.8s redirect fires.
      await tester.pumpWidgetBuilder(
        _harness(hasSeenOnboarding: true, hasSession: true, brightness: Brightness.light),
        surfaceSize: const Size(390, 844),
      );
      await tester.pump(const Duration(milliseconds: 1000));
      await screenMatchesGolden(
        tester,
        'splash_screen_light',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 10)),
      );
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        _harness(hasSeenOnboarding: true, hasSession: true),
        surfaceSize: const Size(390, 844),
      );
      await tester.pump(const Duration(milliseconds: 1000));
      await screenMatchesGolden(
        tester,
        'splash_screen_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 10)),
      );
    });
  });
}
