import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart' show PlatformException;
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';

/// Why an unlock attempt did not succeed.
///
/// This exists because the previous version returned a bare `bool` and
/// swallowed every exception into `false`. The Profile toggle could then only
/// say "Authentication failed or was cancelled", which was reported as a bug
/// and was in fact three different bugs wearing one message: no fingerprint
/// enrolled, the OS sheet never opening at all, and a genuine cancel.
///
/// The one that mattered was the middle one — `local_auth` needs the host
/// Activity to be a `FlutterFragmentActivity` and throws
/// `no_fragment_activity` otherwise, so the prompt never appeared. A user
/// told "authentication failed" will retry forever; a user told what is
/// actually wrong can act on it.
enum BiometricFailure {
  /// The user dismissed the prompt. Not an error — no message needed.
  cancelled,

  /// Hardware is present but the user has not enrolled a fingerprint/face.
  notEnrolled,

  /// No biometric hardware, or the platform does not support it.
  unavailable,

  /// Too many failed attempts; the OS has locked biometrics temporarily.
  lockedOut,

  /// Locked out until the device passcode is entered.
  permanentlyLockedOut,

  /// The plugin could not show its prompt — almost always the host Activity
  /// not being a `FlutterFragmentActivity`. A build defect, not a user one.
  notConfigured,

  /// The biometric matched nothing, or something unrecognised went wrong.
  failed,
}

/// The outcome of an unlock attempt.
sealed class BiometricResult {
  const BiometricResult();
}

class BiometricSuccess extends BiometricResult {
  const BiometricSuccess();
}

class BiometricRejected extends BiometricResult {
  const BiometricRejected(this.reason, {this.detail});

  final BiometricFailure reason;

  /// The raw platform message, for logs. Never shown verbatim to the user.
  final String? detail;

  /// What to tell the user. Null when there is nothing worth saying —
  /// they cancelled, and they know they cancelled.
  String? userMessage(String platformLabel) => switch (reason) {
    BiometricFailure.cancelled => null,
    BiometricFailure.notEnrolled =>
      'No $platformLabel is set up on this phone. Add one in your device '
          'settings, then turn this on again.',
    BiometricFailure.unavailable =>
      "This phone doesn't support $platformLabel unlock.",
    BiometricFailure.lockedOut =>
      'Too many attempts. Wait a moment and try again.',
    BiometricFailure.permanentlyLockedOut =>
      'Biometrics are locked. Unlock your phone with your PIN or password '
          'first, then try again.',
    BiometricFailure.notConfigured =>
      "$platformLabel unlock isn't available in this build of SafeHer.",
    BiometricFailure.failed => "That didn't match. Try again.",
  };
}

/// Thin wrapper around `local_auth` for the Profile > Security biometric
/// toggle.
///
/// Deliberately does not swallow failures into a single `false` any more —
/// see [BiometricFailure]. It still never throws: the caller is a settings
/// toggle, not a code path that can handle an exception mid-emergency.
class BiometricService {
  BiometricService({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  Future<bool> get isAvailable async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (_) {
      return false;
    }
  }

  /// Whether the user has actually enrolled a fingerprint or face.
  ///
  /// Distinct from [isAvailable], which only says the hardware exists. A
  /// phone with a fingerprint reader and nothing enrolled passes
  /// `canCheckBiometrics` and then fails at the prompt, which is exactly the
  /// confusing path this separates out.
  Future<bool> get hasEnrolledBiometrics async {
    try {
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  String get platformLabel => defaultTargetPlatform == TargetPlatform.iOS ? 'Face ID' : 'Fingerprint';

  /// Prompts the OS biometric UI and reports precisely what happened.
  Future<BiometricResult> authenticate({required String reason}) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      return ok
          ? const BiometricSuccess()
          : const BiometricRejected(BiometricFailure.cancelled);
    } on PlatformException catch (error) {
      return BiometricRejected(_mapCode(error.code), detail: error.message);
    } catch (error) {
      return BiometricRejected(BiometricFailure.failed, detail: error.toString());
    }
  }

  BiometricFailure _mapCode(String code) => switch (code) {
    auth_error.notEnrolled => BiometricFailure.notEnrolled,
    auth_error.notAvailable => BiometricFailure.unavailable,
    auth_error.passcodeNotSet => BiometricFailure.notEnrolled,
    auth_error.lockedOut => BiometricFailure.lockedOut,
    auth_error.permanentlyLockedOut => BiometricFailure.permanentlyLockedOut,
    // Not in `error_codes.dart`, but the one that actually bit this project:
    // thrown when the host Activity is not a FlutterFragmentActivity, so the
    // prompt never renders and every attempt looks like a user failure.
    'no_fragment_activity' => BiometricFailure.notConfigured,
    'NoActivity' => BiometricFailure.notConfigured,
    _ => BiometricFailure.failed,
  };
}
