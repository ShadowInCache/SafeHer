import '../domain/auth_repository.dart';

/// Fixture-backed auth repository used while [AppFlavor.isMock] is true.
/// No session is ever persisted here — real sign-in state arrives with the
/// Firebase-backed implementation in Phase 4.
class AuthRepositoryMock implements AuthRepository {
  @override
  Future<bool> hasActiveSession() async {
    await Future.delayed(const Duration(milliseconds: 150));
    return false;
  }

  @override
  Future<void> signInWithEmail({required String email, required String password}) async {
    await Future.delayed(const Duration(milliseconds: 400));
    // Deterministic mock rule so tests can trigger success/failure without
    // depending on a hardcoded "correct" credential: real validation
    // arrives with Phase 4's Firebase-backed implementation.
    if (password.length < 6) {
      throw const AuthException('Incorrect email or password.');
    }
  }

  @override
  Future<void> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String phoneE164,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 400));
    // Deterministic mock rule for testing the failure path, same spirit as
    // signInWithEmail's password-length rule.
    if (email.toLowerCase().startsWith('taken@')) {
      throw const AuthException('An account with this email already exists.');
    }
  }

  @override
  Future<void> verifyOtp(String code) async {
    await Future.delayed(const Duration(milliseconds: 400));
    // Deterministic mock rule, same spirit as the other mock methods.
    if (code != '123456') {
      throw const AuthException('Incorrect code. Please try again.');
    }
  }

  @override
  Future<void> resendOtp() async {
    await Future.delayed(const Duration(milliseconds: 300));
  }
}
