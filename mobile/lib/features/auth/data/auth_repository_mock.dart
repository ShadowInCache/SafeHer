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
}
