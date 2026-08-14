import 'package:safeher_app/features/auth/domain/auth_repository.dart';

/// Stand-in for [AuthRepository] in widget tests.
///
/// Any screen that can sign out, delete an account, or read session state
/// needs this override. Without it the test reaches the real Firebase-backed
/// repository, which either throws `[core/no-app]` or hangs on a platform
/// channel that doesn't exist under `flutter test`.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.activeSession = true});

  final bool activeSession;

  /// Method names in call order, so tests can assert what the UI actually did.
  final List<String> calls = [];

  @override
  bool phoneVerificationUnavailable = false;

  @override
  Future<bool> hasActiveSession() async => activeSession;

  @override
  Future<void> signOut() async => calls.add('signOut');

  @override
  Future<void> deleteAccount() async => calls.add('deleteAccount');

  @override
  Future<void> signInWithEmail({required String email, required String password}) async =>
      calls.add('signInWithEmail');

  @override
  Future<void> signInAsGuest() async => calls.add('signInAsGuest');

  @override
  Future<void> signInWithGoogle() async => calls.add('signInWithGoogle');

  @override
  Future<void> signInWithApple() async => calls.add('signInWithApple');

  @override
  Future<void> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String phoneE164,
    required String password,
  }) async => calls.add('signUp');

  @override
  Future<void> verifyOtp(String code) async => calls.add('verifyOtp');

  @override
  Future<void> resendOtp() async => calls.add('resendOtp');

  @override
  Future<void> sendPasswordResetEmail(String email) async => calls.add('sendPasswordResetEmail');
}
