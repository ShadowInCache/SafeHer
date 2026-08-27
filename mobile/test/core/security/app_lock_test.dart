import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safeher_app/core/biometrics/biometric_providers.dart';
import 'package:safeher_app/core/biometrics/biometric_service.dart';
import 'package:safeher_app/core/local/onboarding_prefs.dart';
import 'package:safeher_app/core/router/app_router.dart';
import 'package:safeher_app/core/security/app_lock.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/auth/data/auth_providers.dart';
import 'package:safeher_app/features/auth/domain/auth_repository.dart';

import '../../test_utils/fake_key_value_store.dart';

/// The setting used to be decoration: enabling it prompted once, wrote a
/// flag, and nothing ever read the flag again. These tests are the reason it
/// cannot silently become decoration a second time.
class _FakeBiometricService implements BiometricService {
  _FakeBiometricService({
    this.available = true,
    this.enrolled = true,
    this.result = const BiometricSuccess(),
  });

  bool available;
  bool enrolled;
  BiometricResult result;
  int prompts = 0;
  bool? lastAllowedDeviceCredential;

  @override
  Future<bool> get isAvailable async => available;

  @override
  Future<bool> get hasEnrolledBiometrics async => enrolled;

  @override
  String get platformLabel => 'Fingerprint';

  @override
  Future<BiometricResult> authenticate({
    required String reason,
    bool allowDeviceCredential = false,
  }) async {
    prompts++;
    lastAllowedDeviceCredential = allowDeviceCredential;
    return result;
  }
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.signedIn = true});
  final bool signedIn;

  @override
  Future<bool> hasActiveSession() async => signedIn;

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Widget _harness({
  required FakeKeyValueStore store,
  required _FakeBiometricService biometrics,
  bool signedIn = true,
}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const Scaffold(body: Text('SECRET-HOME'))),
      GoRoute(path: '/emergency', builder: (_, __) => const Scaffold(body: Text('EMERGENCY-SCREEN'))),
    ],
  );
  return ProviderScope(
    overrides: [
      localKeyValueStoreProvider.overrideWithValue(store),
      biometricServiceProvider.overrideWithValue(biometrics),
      authRepositoryProvider.overrideWithValue(_FakeAuthRepository(signedIn: signedIn)),
      appRouterProvider.overrideWithValue(router),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: router,
      builder: (context, child) => AppLock(child: child ?? const SizedBox.shrink()),
    ),
  );
}

/// The lock hides the app by excluding it from the semantics tree and
/// ignoring pointers, not by unmounting it.
bool _lockedContentIsHidden(WidgetTester tester) {
  // "Any ancestor", not "the nearest": MaterialApp and Scaffold put their own
  // ExcludeSemantics/IgnorePointer in the tree, and the nearest one is
  // usually theirs rather than the lock's.
  final excluded = find
      .ancestor(of: find.text('SECRET-HOME'), matching: find.byType(ExcludeSemantics))
      .evaluate()
      .any((e) => (e.widget as ExcludeSemantics).excluding);
  final ignored = find
      .ancestor(of: find.text('SECRET-HOME'), matching: find.byType(IgnorePointer))
      .evaluate()
      .any((e) => (e.widget as IgnorePointer).ignoring);
  return excluded && ignored;
}

void main() {
  group('AppLock', () {
    late FakeKeyValueStore store;

    setUp(() => store = FakeKeyValueStore());

    Future<void> enableBiometrics() => store.setBool('biometricEnabled', true);

    testWidgets('does nothing when the setting is off', (tester) async {
      final biometrics = _FakeBiometricService();
      await tester.pumpWidget(_harness(store: store, biometrics: biometrics));
      await tester.pumpAndSettle();

      expect(find.text('SECRET-HOME'), findsOneWidget);
      expect(find.text('Unlock SafeHer'), findsNothing);
      expect(biometrics.prompts, 0, reason: 'an off switch must never prompt');
    });

    testWidgets('locks on launch when enabled, hiding the app behind it', (tester) async {
      await enableBiometrics();
      // Rejected, so the lock stays up and can be inspected.
      final biometrics = _FakeBiometricService(
        result: const BiometricRejected(BiometricFailure.cancelled),
      );

      await tester.pumpWidget(_harness(store: store, biometrics: biometrics));
      await tester.pumpAndSettle();

      expect(find.text('Unlock SafeHer'), findsOneWidget);
      expect(biometrics.prompts, greaterThan(0), reason: 'the flag must actually be used');
      expect(_lockedContentIsHidden(tester), isTrue,
          reason: 'a screen reader must not read out what the lock covers');
    });

    testWidgets('a successful prompt reveals the app', (tester) async {
      await enableBiometrics();
      final biometrics = _FakeBiometricService();

      await tester.pumpWidget(_harness(store: store, biometrics: biometrics));
      await tester.pumpAndSettle();

      expect(find.text('Unlock SafeHer'), findsNothing);
      expect(find.text('SECRET-HOME'), findsOneWidget);
    });

    testWidgets('unlocking offers the device credential as a fallback', (tester) async {
      // biometricOnly leaves no way in when the reader will not read, which
      // for a safety app is a locked door with no key.
      await enableBiometrics();
      final biometrics = _FakeBiometricService();

      await tester.pumpWidget(_harness(store: store, biometrics: biometrics));
      await tester.pumpAndSettle();

      expect(biometrics.lastAllowedDeviceCredential, isTrue);
    });

    testWidgets('does not lock when nobody is signed in', (tester) async {
      await enableBiometrics();
      final biometrics = _FakeBiometricService();

      await tester.pumpWidget(
        _harness(store: store, biometrics: biometrics, signedIn: false),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unlock SafeHer'), findsNothing);
      expect(biometrics.prompts, 0, reason: 'locking the login screen would strand the user');
    });

    testWidgets('fails open and disables itself when biometrics are gone', (tester) async {
      await enableBiometrics();
      final biometrics = _FakeBiometricService(available: false, enrolled: false);

      await tester.pumpWidget(_harness(store: store, biometrics: biometrics));
      await tester.pumpAndSettle();

      expect(find.text('Unlock SafeHer'), findsNothing, reason: 'must not seal the app shut');
      expect(store.getBool('biometricEnabled'), isFalse,
          reason: 'a setting that can no longer be satisfied should turn itself off');
    });

    testWidgets('Emergency SOS reaches the alarm without unlocking the app', (tester) async {
      await enableBiometrics();
      final biometrics = _FakeBiometricService(
        result: const BiometricRejected(BiometricFailure.cancelled),
      );

      await tester.pumpWidget(_harness(store: store, biometrics: biometrics));
      await tester.pumpAndSettle();
      expect(find.text('Unlock SafeHer'), findsOneWidget);

      await tester.tap(find.text('Emergency SOS'));
      await tester.pumpAndSettle();

      expect(find.text('EMERGENCY-SCREEN'), findsOneWidget,
          reason: 'a fingerprint must never stand between someone and help');
      expect(find.text('Unlock SafeHer'), findsNothing);
    });

    testWidgets('leaving the emergency screen re-locks immediately', (tester) async {
      // The bypass is a door into the alarm, not a way around the lock.
      await enableBiometrics();
      final biometrics = _FakeBiometricService(
        result: const BiometricRejected(BiometricFailure.cancelled),
      );

      await tester.pumpWidget(_harness(store: store, biometrics: biometrics));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Emergency SOS'));
      await tester.pumpAndSettle();
      expect(find.text('EMERGENCY-SCREEN'), findsOneWidget);

      // Navigate back to the protected part of the app, the way the app would.
      GoRouter.of(tester.element(find.text('EMERGENCY-SCREEN'))).go('/home');
      await tester.pumpAndSettle();

      expect(find.text('Unlock SafeHer'), findsOneWidget,
          reason: 'the lock must return the moment the emergency route is left');
      // The app deliberately stays mounted underneath -- tearing it down would
      // drop live monitoring -- so "hidden" is asserted the way it is actually
      // enforced: no semantics, no pointers.
      expect(_lockedContentIsHidden(tester), isTrue);
    });
  });
}
