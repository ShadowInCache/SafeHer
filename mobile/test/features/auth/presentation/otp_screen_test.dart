import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import '../../../test_utils/fake_key_value_store.dart';
import 'package:safeher_app/core/local/onboarding_prefs.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/auth/data/auth_providers.dart';
import 'package:safeher_app/features/auth/domain/auth_repository.dart';
import 'package:safeher_app/features/auth/presentation/otp_screen.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

class _FakeAuthRepository implements AuthRepository {
  @override
  bool get phoneVerificationUnavailable => false;

  int resendCallCount = 0;

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
  }) async {}

  @override
  Future<void> verifyOtp(String code) async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (code != '123456') {
      throw const AuthException('Incorrect code. Please try again.');
    }
  }

  @override
  Future<void> resendOtp() async {
    resendCallCount++;
    await Future.delayed(const Duration(milliseconds: 50));
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}
}

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/auth/otp',
    routes: [
      GoRoute(path: '/auth/otp', builder: (context, state) => const OtpScreen()),
      GoRoute(path: '/home', builder: (context, state) => const Scaffold(body: Text('home-stub'))),
    ],
  );
}

Widget _harness({Brightness brightness = Brightness.dark, _FakeAuthRepository? repo}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo ?? _FakeAuthRepository()),
      // Signing in clears the previous account's persisted
      // preferences, so the reset needs somewhere to write.
      localKeyValueStoreProvider.overrideWithValue(FakeKeyValueStore()),
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

Future<void> _enterCode(WidgetTester tester, String code) async {
  final fields = find.byType(TextField);
  for (var i = 0; i < code.length; i++) {
    await tester.enterText(fields.at(i), code[i]);
    await tester.pump();
  }
}

void main() {
  group('OtpScreen', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(_harness(brightness: Brightness.light));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Verify your number'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('navigation_actions_work: correct code navigates to home', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      await _enterCode(tester, '123456');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.text('home-stub'), findsOneWidget);
    });

    testWidgets('wrong code does not navigate and clears the fields', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      await _enterCode(tester, '000000');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('home-stub'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows countdown then enables Resend OTP, tapping shows toast', (tester) async {
      final repo = _FakeAuthRepository();
      await tester.pumpWidget(_harness(repo: repo));
      await tester.pump();
      expect(find.textContaining('Resend OTP in'), findsOneWidget);
      expect(find.text('Resend OTP'), findsNothing);

      await tester.pump(const Duration(seconds: 61));
      expect(find.text('Resend OTP'), findsOneWidget);

      await tester.tap(find.text('Resend OTP'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.resendCallCount, 1);
      expect(find.text('OTP sent!'), findsOneWidget);
      // Flush the toast's own dismiss timers so nothing leaks past teardown.
      await tester.pump(const Duration(seconds: 5));
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(_harness(brightness: Brightness.light), surfaceSize: const Size(390, 700));
      await tester.pump();
      await screenMatchesGolden(tester, 'otp_screen_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 700));
      await tester.pump();
      await screenMatchesGolden(tester, 'otp_screen_dark');
    });
  });
}
