import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/auth/data/auth_providers.dart';
import 'package:safeher_app/features/auth/domain/auth_repository.dart';
import 'package:safeher_app/features/auth/presentation/forgot_password_screen.dart';

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<bool> hasActiveSession() async => false;

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
  Future<void> sendPasswordResetEmail(String email) async {
    await Future.delayed(const Duration(milliseconds: 50));
  }
}

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/auth/forgot',
    routes: [
      GoRoute(path: '/auth/forgot', builder: (context, state) => const ForgotPasswordScreen()),
      GoRoute(path: '/auth/login', builder: (context, state) => const Scaffold(body: Text('login-stub'))),
    ],
  );
}

Widget _harness({Brightness brightness = Brightness.dark}) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(_FakeAuthRepository())],
    child: MaterialApp.router(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      routerConfig: _buildTestRouter(),
    ),
  );
}

void main() {
  group('ForgotPasswordScreen', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(_harness(brightness: Brightness.light));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Reset your password'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows error when email is empty', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.tap(find.text('Send Reset Link'));
      await tester.pump();
      expect(find.text('Email is required'), findsOneWidget);
    });

    testWidgets('handles tap and shows confirmation after sending', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.enterText(find.bySemanticsLabel('Email'), 'user@example.com');
      await tester.tap(find.text('Send Reset Link'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Check your email'), findsOneWidget);
      expect(find.textContaining('user@example.com'), findsOneWidget);
    });

    testWidgets('navigation_actions_work: Back to Sign In navigates to login', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.enterText(find.bySemanticsLabel('Email'), 'user@example.com');
      await tester.tap(find.text('Send Reset Link'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Back to Sign In'));
      await tester.pumpAndSettle();
      expect(find.text('login-stub'), findsOneWidget);
    });

    testWidgets('back button navigates to login', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(find.text('login-stub'), findsOneWidget);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(_harness(brightness: Brightness.light), surfaceSize: const Size(390, 700));
      await tester.pump();
      await screenMatchesGolden(tester, 'forgot_password_screen_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 700));
      await tester.pump();
      await screenMatchesGolden(tester, 'forgot_password_screen_dark');
    });
  });
}
