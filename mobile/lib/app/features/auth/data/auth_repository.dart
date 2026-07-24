import '../../../shared/models/domain_models.dart';

class AuthSession {
  final AppUser user;
  final String jwt;

  const AuthSession({required this.user, required this.jwt});
}

abstract class AuthRepository {
  bool get firebaseReady;

  Future<AuthSession> loginWithEmail({
    required String email,
    required String password,
    required AppRole role,
  });

  Future<AuthSession> signUpWithEmail({
    required String fullName,
    required String email,
    required String password,
    required String? phone,
    required AppRole role,
  });

  Future<AuthSession> loginWithGoogle({required AppRole role});

  Future<String> requestPhoneOtp(String phoneNumber);

  Future<AuthSession> verifyPhoneOtp({
    required String verificationId,
    required String smsCode,
    required AppRole role,
  });

  Future<void> requestPasswordReset(String email);

  Future<void> logout();
}
