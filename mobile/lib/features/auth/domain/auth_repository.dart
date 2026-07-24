/// Thrown by [AuthRepository] methods on invalid credentials or other
/// auth-domain failures. The message is safe to show directly to the user.
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Abstract session/auth interface. See data/ for the mock (dev flavor) and
/// eventual Firebase-backed (prod flavor) implementations.
abstract class AuthRepository {
  Future<bool> hasActiveSession();

  Future<void> signInWithEmail({required String email, required String password});

  Future<void> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String phoneE164,
    required String password,
  });

  Future<void> verifyOtp(String code);

  Future<void> resendOtp();
}
