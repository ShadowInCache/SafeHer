import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/auth/data/auth_providers.dart';
import 'package:safeher_app/features/auth/domain/auth_repository.dart';
import 'package:safeher_app/features/auth/presentation/login_screen.dart';

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.shouldFail = false});
  final bool shouldFail;

  @override
  Future<bool> hasActiveSession() async => false;

  @override
  Future<void> signInWithEmail({required String email, required String password}) async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (shouldFail) throw const AuthException('Incorrect email or password.');
  }

  @override
  Future<void> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String phoneE164,
    required String password,
  }) async {}
}

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/auth/login',
    routes: [
      GoRoute(path: '/auth/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/home', builder: (context, state) => const Scaffold(body: Text('home-stub'))),
      GoRoute(path: '/auth/signup', builder: (context, state) => const Scaffold(body: Text('signup-stub'))),
      GoRoute(path: '/auth/forgot', builder: (context, state) => const Scaffold(body: Text('forgot-stub'))),
    ],
  );
}

Widget _harness({Brightness brightness = Brightness.dark, bool shouldFail = false}) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(_FakeAuthRepository(shouldFail: shouldFail))],
    child: MaterialApp.router(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      routerConfig: _buildTestRouter(),
    ),
  );
}

void main() {
  group('LoginScreen', () {
    Future<void> useRealisticSurface(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }

    testWidgets('renders in light mode', (tester) async {
      await useRealisticSurface(tester);
      await tester.pumpWidget(_harness(brightness: Brightness.light));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await useRealisticSurface(tester);
      await tester.pumpWidget(_harness());
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('shows error when email is empty', (tester) async {
      await useRealisticSurface(tester);
      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.tap(find.text('Sign In'));
      await tester.pump();
      expect(find.text('Email is required'), findsOneWidget);
    });

    testWidgets('shows error for invalid email format', (tester) async {
      await useRealisticSurface(tester);
      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.enterText(find.bySemanticsLabel('Email'), 'not-an-email');
      await tester.tap(find.text('Sign In'));
      await tester.pump();
      expect(find.text('Enter a valid email address'), findsOneWidget);
    });

    testWidgets('shows coral toast on wrong credentials', (tester) async {
      await useRealisticSurface(tester);
      await tester.pumpWidget(_harness(shouldFail: true));
      await tester.pump();
      await tester.enterText(find.bySemanticsLabel('Email'), 'user@example.com');
      await tester.enterText(find.bySemanticsLabel('Password'), 'password123');
      await tester.tap(find.text('Sign In'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Incorrect email or password.'), findsOneWidget);
      // Flush the toast's own dismiss timers so nothing leaks past teardown.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('navigation_actions_work: valid sign-in navigates to home', (tester) async {
      await useRealisticSurface(tester);
      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.enterText(find.bySemanticsLabel('Email'), 'user@example.com');
      await tester.enterText(find.bySemanticsLabel('Password'), 'password123');
      await tester.tap(find.text('Sign In'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // GoRouter needs one more frame after context.go() to rebuild.
      await tester.pump();
      expect(find.text('home-stub'), findsOneWidget);
    });

    testWidgets('handles tap on Create account link', (tester) async {
      await useRealisticSurface(tester);
      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(find.text('signup-stub'), findsOneWidget);
    });

    testWidgets('handles tap on Forgot link', (tester) async {
      await useRealisticSurface(tester);
      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.tap(find.text('Forgot?'));
      await tester.pumpAndSettle();
      expect(find.text('forgot-stub'), findsOneWidget);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(_harness(brightness: Brightness.light), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 400));
      await screenMatchesGolden(tester, 'login_screen_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 400));
      await screenMatchesGolden(tester, 'login_screen_dark');
    });
  });
}
