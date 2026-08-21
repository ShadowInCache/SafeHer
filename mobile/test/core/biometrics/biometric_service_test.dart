import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:safeher_app/core/biometrics/biometric_service.dart';

/// Why this file exists.
///
/// Enabling biometric unlock on a real phone reported "Authentication failed
/// or was cancelled" every single time, and the fingerprint sheet never
/// appeared at all. The service caught every exception and returned a bare
/// `false`, so three unrelated causes — no fingerprint enrolled, a genuine
/// cancel, and the plugin being unable to show its prompt — arrived at the UI
/// as one message that described only the least likely of them.
///
/// The real cause was the third: `local_auth` renders the AndroidX
/// BiometricPrompt, which is a Fragment, so the host Activity has to be a
/// `FlutterFragmentActivity`. Under a plain `FlutterActivity` the plugin
/// throws `no_fragment_activity` before anything is shown. That is a build
/// defect, and telling the user "authentication failed" invites her to retry
/// the one thing that can never work.
///
/// These tests pin the mapping. The Activity itself is fixed in
/// `MainActivity.kt`, which no Dart test can reach.
class _ThrowingAuth implements LocalAuthentication {
  _ThrowingAuth(this.error);

  final Object error;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object> authMessages = const [],
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async => throw error;

  @override
  Future<bool> get canCheckBiometrics async => true;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => [BiometricType.fingerprint];

  @override
  Future<bool> stopAuthentication() async => true;
}

class _RefusingAuth implements LocalAuthentication {
  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object> authMessages = const [],
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async => false;

  @override
  Future<bool> get canCheckBiometrics async => true;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => const [];

  @override
  Future<bool> stopAuthentication() async => true;
}

void main() {
  group('BiometricService', () {
    test('the missing FragmentActivity is named as a build problem', () async {
      // The bug that produced the report. It must not be reported as the
      // user failing to authenticate.
      final service = BiometricService(
        auth: _ThrowingAuth(
          PlatformException(
            code: 'no_fragment_activity',
            message: 'local_auth plugin requires activity to be a FragmentActivity.',
          ),
        ),
      );

      final result = await service.authenticate(reason: 'test');

      expect(result, isA<BiometricRejected>());
      expect((result as BiometricRejected).reason, BiometricFailure.notConfigured);
      expect(
        result.userMessage('Fingerprint'),
        isNot(contains('failed')),
        reason: 'this is a build defect, not a failed attempt',
      );
    });

    test('nothing enrolled is told apart from a failed match', () async {
      final service = BiometricService(
        auth: _ThrowingAuth(PlatformException(code: 'NotEnrolled')),
      );

      final result = await service.authenticate(reason: 'test');

      expect((result as BiometricRejected).reason, BiometricFailure.notEnrolled);
      // Actionable: it says where to go and what to do.
      expect(result.userMessage('Fingerprint'), contains('device settings'));
    });

    test('a lockout says to wait rather than to try again', () async {
      final service = BiometricService(
        auth: _ThrowingAuth(PlatformException(code: 'LockedOut')),
      );

      final result = await service.authenticate(reason: 'test');

      expect((result as BiometricRejected).reason, BiometricFailure.lockedOut);
    });

    test('a permanent lockout points at the device passcode', () async {
      final service = BiometricService(
        auth: _ThrowingAuth(PlatformException(code: 'PermanentlyLockedOut')),
      );

      final result = await service.authenticate(reason: 'test');

      expect(
        (result as BiometricRejected).reason,
        BiometricFailure.permanentlyLockedOut,
      );
      expect(result.userMessage('Fingerprint'), contains('PIN'));
    });

    test('a cancel gets no message at all', () async {
      // She dismissed the sheet on purpose and does not need to be told what
      // she just did — and it certainly is not an error.
      final service = BiometricService(auth: _RefusingAuth());

      final result = await service.authenticate(reason: 'test');

      expect((result as BiometricRejected).reason, BiometricFailure.cancelled);
      expect(result.userMessage('Fingerprint'), isNull);
    });

    test('hasEnrolledBiometrics is separate from hardware being present', () async {
      // `canCheckBiometrics` is true on a phone with a reader and nothing
      // enrolled — which then fails at the prompt. Separating the two is what
      // lets the toggle say so before showing a sheet that cannot succeed.
      final service = BiometricService(auth: _RefusingAuth());

      expect(await service.isAvailable, isTrue);
      expect(await service.hasEnrolledBiometrics, isFalse);
    });
  });
}
