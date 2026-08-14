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

  /// True when sign-up created the account but phone verification could not
  /// be started (provider disabled, unregistered SHA-1, SMS quota). The
  /// account is still usable — the OTP screen uses this to say so plainly
  /// rather than waiting for a code that will never arrive.
  bool get phoneVerificationUnavailable;

  Future<void> signInWithEmail({required String email, required String password});

  /// Google Sign-In. Requires the app's Firebase project to have Google as
  /// an enabled sign-in provider and (on Android) the release/debug SHA-1
  /// fingerprints registered in the Firebase console — otherwise this
  /// throws [AuthException] with a message explaining that.
  Future<void> signInWithGoogle();

  /// Anonymous "guest" sign-in.
  ///
  /// Gets someone to the SOS button without an account, which matters for a
  /// safety app: the moment help is needed is the worst moment to be filling in
  /// a sign-up form. The backend still provisions a real account, keyed to the
  /// Firebase uid, so contacts and incidents persist and the guest can be
  /// upgraded to a full account later.
  ///
  /// Requires the Anonymous provider to be enabled in the Firebase console;
  /// otherwise this throws [AuthException] explaining that.
  Future<void> signInAsGuest();

  /// Apple Sign-In (iOS only — callers gate this behind `Platform.isIOS`).
  /// Requires the "Sign in with Apple" capability enabled in the app's
  /// Apple Developer account and configured in the Firebase console —
  /// otherwise this throws [AuthException] with a message explaining that.
  Future<void> signInWithApple();

  Future<void> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String phoneE164,
    required String password,
  });

  Future<void> verifyOtp(String code);

  Future<void> resendOtp();

  Future<void> sendPasswordResetEmail(String email);

  Future<void> signOut();

  /// Permanently deletes the signed-in user's account. Firebase requires a
  /// recent sign-in for this — if the session is stale this throws
  /// [AuthException] asking the user to sign in again before retrying.
  Future<void> deleteAccount();
}
