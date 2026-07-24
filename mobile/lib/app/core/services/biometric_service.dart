import 'package:local_auth/local_auth.dart';

class BiometricService {
  final LocalAuthentication _localAuth = LocalAuthentication();

  Future<bool> canUseBiometrics() async {
    final isSupported = await _localAuth.isDeviceSupported();
    final canCheck = await _localAuth.canCheckBiometrics;
    return isSupported && canCheck;
  }

  Future<bool> authenticate({String reason = 'Verify your identity'}) async {
    final canUse = await canUseBiometrics();
    if (!canUse) {
      return false;
    }

    return _localAuth.authenticate(
      localizedReason: reason,
      options: const AuthenticationOptions(
        biometricOnly: false,
        stickyAuth: true,
        useErrorDialogs: true,
      ),
    );
  }
}
