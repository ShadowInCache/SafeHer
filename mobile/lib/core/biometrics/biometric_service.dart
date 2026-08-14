import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:local_auth/local_auth.dart';

/// Thin wrapper around `local_auth` for the Profile > Security biometric
/// toggle. Never throws — every failure mode resolves to `false` so the UI
/// can show a clear message instead of crashing.
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

  String get platformLabel => defaultTargetPlatform == TargetPlatform.iOS ? 'Face ID' : 'Fingerprint';

  /// Prompts the OS biometric UI. Returns false (not an error) on any
  /// failure — cancellation, lockout, hardware unavailable, etc.
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }
}
