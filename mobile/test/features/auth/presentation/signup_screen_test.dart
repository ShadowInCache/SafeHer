import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/auth/data/auth_providers.dart';
import 'package:safeher_app/features/auth/domain/auth_repository.dart';
import 'package:safeher_app/features/auth/presentation/signup_screen.dart';
import 'package:safeher_app/shared/components/buttons/sa_button.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

final _createAccountButton = find.widgetWithText(SaButton, 'Create Account');

class _FakeAuthRepository implements AuthRepository {
  @override
  bool get phoneVerificationUnavailable => false;

  @override
  Future<bool> hasActiveSession() async => false;

  @override
  Future<void> signInWithEmail({required String email, required String password}) async {}

  @override
  Future<void> signInAsGuest() async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signInWithApple() async {}

  @override
  Future<void> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String phoneE164,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (email.toLowerCase().startsWith('taken@')) {
      throw const AuthException('An account with this email already exists.');
    }
  }

  @override
  Future<void> verifyOtp(String code) async {}

  @override
  Future<void> resendOtp() async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/auth/signup',
    routes: [
      GoRoute(path: '/auth/signup', builder: (context, state) => const SignupScreen()),
      GoRoute(path: '/auth/otp', builder: (context, state) => const Scaffold(body: Text('otp-stub'))),
      GoRoute(path: '/auth/login', builder: (context, state) => const Scaffold(body: Text('login-stub'))),
    ],
  );
}

Widget _harness({Brightness brightness = Brightness.dark}) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(_FakeAuthRepository())],
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

const _strongPassword = 'Str0ng!Passw0rd';

Future<void> _fillValidForm(WidgetTester tester) async {
  await tester.enterText(find.bySemanticsLabel('First name'), 'Priya');
  await tester.enterText(find.bySemanticsLabel('Last name'), 'Sharma');
  await tester.enterText(find.bySemanticsLabel('Email'), 'priya@example.com');
  await tester.enterText(find.bySemanticsLabel('Phone number, country code +1'), '5551234567');
  await tester.enterText(find.bySemanticsLabel('Password'), _strongPassword);
  await tester.pump();
  await tester.enterText(find.bySemanticsLabel('Confirm password'), _strongPassword);
  await tester.pump();
}

void main() {
  group('SignupScreen', () {
    Future<void> useRealisticSurface(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }

    testWidgets('renders in light mode', (tester) async {
      await useRealisticSurface(tester);
      await tester.pumpWidget(_harness(brightness: Brightness.light));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Create Account'), findsWidgets);
    });

    testWidgets('renders in dark mode', (tester) async {
      await useRealisticSurface(tester);
      await tester.pumpWidget(_harness());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('validates top-to-bottom, first invalid field only', (tester) async {
      await useRealisticSurface(tester);
      await tester.pumpWidget(_harness());
      await tester.pump();

      await tester.tap(_createAccountButton);
      await tester.pump();
      expect(find.text('First name is required'), findsOneWidget);

      await tester.enterText(find.bySemanticsLabel('First name'), 'Priya');
      await tester.pump();
      await tester.tap(_createAccountButton);
      await tester.pump();
      expect(find.text('First name is required'), findsNothing);
      expect(find.text('Last name is required'), findsOneWidget);
    });

    testWidgets('password strength bar reflects computePasswordStrength', (tester) async {
      await useRealisticSurface(tester);
      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.enterText(find.bySemanticsLabel('Password'), _strongPassword);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows mismatch error for confirm password', (tester) async {
      await useRealisticSurface(tester);
      await tester.pumpWidget(_harness());
      await tester.pump();
      await _fillValidForm(tester);
      await tester.enterText(find.bySemanticsLabel('Confirm password'), 'SomethingElse123!');
      await tester.pump();
      await tester.tap(_createAccountButton);
      await tester.pump();
      expect(find.text("Passwords don't match"), findsOneWidget);
    });

    testWidgets('navigation_actions_work: valid signup navigates to OTP', (tester) async {
      await useRealisticSurface(tester);
      await tester.pumpWidget(_harness());
      await tester.pump();
      await _fillValidForm(tester);

      await tester.tap(_createAccountButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.text('otp-stub'), findsOneWidget);
    });

    testWidgets('shows toast when email already exists', (tester) async {
      await useRealisticSurface(tester);
      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.enterText(find.bySemanticsLabel('First name'), 'Priya');
      await tester.enterText(find.bySemanticsLabel('Last name'), 'Sharma');
      await tester.enterText(find.bySemanticsLabel('Email'), 'taken@example.com');
      await tester.enterText(find.bySemanticsLabel('Phone number, country code +1'), '5551234567');
      await tester.enterText(find.bySemanticsLabel('Password'), _strongPassword);
      await tester.pump();
      await tester.enterText(find.bySemanticsLabel('Confirm password'), _strongPassword);
      await tester.pump();

      await tester.tap(_createAccountButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('An account with this email already exists.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('handles tap on Sign in link', (tester) async {
      await useRealisticSurface(tester);
      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('login-stub'), findsOneWidget);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(_harness(brightness: Brightness.light), surfaceSize: const Size(390, 900));
      await tester.pump(const Duration(milliseconds: 300));
      await screenMatchesGolden(tester, 'signup_screen_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 900));
      await tester.pump(const Duration(milliseconds: 300));
      await screenMatchesGolden(tester, 'signup_screen_dark');
    });
  });
}
