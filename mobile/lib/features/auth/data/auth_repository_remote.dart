import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/auth_token_store.dart';
import '../domain/auth_repository.dart';

/// Firebase Auth collects the credential (email/password, Google, Apple,
/// phone OTP); `fastapi_app` — not Firestore — is where the resulting
/// account and every other feature's data actually live. So every
/// successful Firebase sign-in is followed by exchanging the Firebase ID
/// token for a `fastapi_app` JWT via `POST /auth/firebase/exchange`
/// (auto-provisions the backend user on first sign-in — see repo root
/// API.md). [ApiClient] then carries that JWT on every subsequent request
/// from any other feature's `*RepositoryRemote`.
class AuthRepositoryRemote implements AuthRepository {
  AuthRepositoryRemote({
    required ApiClient apiClient,
    required AuthTokenStore tokenStore,
    FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  }) : _apiClient = apiClient,
       _tokenStore = tokenStore,
       _injectedAuth = firebaseAuth,
       _injectedGoogleSignIn = googleSignIn;

  final ApiClient _apiClient;
  final AuthTokenStore _tokenStore;
  final FirebaseAuth? _injectedAuth;
  final GoogleSignIn? _injectedGoogleSignIn;

  // Resolved on first use rather than in the constructor: touching
  // `FirebaseAuth.instance` before `Firebase.initializeApp()` has completed
  // throws `[core/no-app]`, which would make merely *constructing* this
  // repository order-dependent on app startup.
  FirebaseAuth? _resolvedAuth;
  FirebaseAuth get _auth => _resolvedAuth ??= _injectedAuth ?? FirebaseAuth.instance;

  GoogleSignIn? _resolvedGoogleSignIn;
  GoogleSignIn get _googleSignIn =>
      _resolvedGoogleSignIn ??= _injectedGoogleSignIn ?? GoogleSignIn(scopes: const ['email', 'profile']);
  String? _phoneVerificationId;
  String? _pendingPhoneE164;

  /// Set when sign-up captured a phone number that Firebase never confirmed.
  /// Still worth persisting to the backend — it's the number the user typed
  /// for their own profile, independent of whether OTP verification ran.
  String? _pendingProfilePhone;

  /// True when [signUp] created the account but couldn't start phone
  /// verification (provider disabled, no SHA-1 registered, SMS quota). The
  /// OTP screen reads this to explain the situation instead of silently
  /// waiting for a code that will never arrive.
  @override
  bool phoneVerificationUnavailable = false;

  @override
  Future<bool> hasActiveSession() async {
    // The backend JWT — not Firebase's currentUser — is what every other
    // repository actually needs to make authenticated calls, so that's the
    // source of truth for "is this app usable right now".
    final token = await _tokenStore.readToken();
    return token != null;
  }

  /// Exchanges the currently-signed-in Firebase user's ID token for a
  /// backend session. Throws [AuthException] if there's no Firebase user
  /// or the backend rejects the token.
  Future<void> _exchangeFirebaseSession() async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthException('Sign-in did not complete. Please try again.');

    // Everything the backend needs to populate the profile on first sign-in.
    // Firebase only ever holds displayName/email/photoURL — the phone the
    // user typed during sign-up lives nowhere else, so it has to travel here
    // or it is lost.
    final phone = _pendingProfilePhone ?? user.phoneNumber;

    try {
      final idToken = await user.getIdToken(true);
      final response = await _apiClient.dio.post(
        '/auth/firebase/exchange',
        data: {
          'id_token': idToken,
          if (user.displayName != null) 'full_name': user.displayName,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          if (user.photoURL != null) 'avatar_url': user.photoURL,
        },
      );
      final accessToken = response.data['access_token'] as String?;
      if (accessToken == null) {
        throw const AuthException('Sign-in failed. Please try again.');
      }
      await _tokenStore.saveSession(
        BackendSession(accessToken: accessToken, refreshToken: response.data['refresh_token'] as String?),
      );
      _pendingProfilePhone = null;
    } on AuthException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageForCode(e.code));
    } catch (error) {
      debugPrint('Firebase session exchange failed: $error');
      throw const AuthException("Couldn't reach the server. Check your connection and try again.");
    }
  }

  @override
  Future<void> signInWithEmail({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageForCode(e.code));
    }
    await _exchangeFirebaseSession();
  }

  @override
  Future<void> signInAsGuest() async {
    try {
      await _auth.signInAnonymously();
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageForCode(e.code));
    }
    await _exchangeFirebaseSession();
  }

  @override
  Future<void> signInWithGoogle() async {
    // On web, Firebase's own popup is the right flow. On Android/iOS the
    // google_sign_in plugin gives the native account picker, whereas
    // signInWithProvider would open a browser sheet.
    if (kIsWeb) {
      try {
        await _auth.signInWithPopup(GoogleAuthProvider());
      } on FirebaseAuthException catch (e) {
        throw AuthException(_messageForCode(e.code));
      }
      await _exchangeFirebaseSession();
      return;
    }

    GoogleSignInAccount? account;
    try {
      account = await _googleSignIn.signIn();
    } catch (error) {
      debugPrint('Google sign-in failed: $error');
      // The overwhelmingly common cause is an Android build whose SHA-1
      // certificate fingerprint isn't registered on the Firebase project, so
      // google-services.json ships with an empty oauth_client list and the
      // plugin fails with a bare PlatformException(sign_in_failed, 10:).
      throw const AuthException(
        "Google sign-in isn't set up for this build yet. "
        'Register the app\'s SHA-1 fingerprint in the Firebase console and '
        'enable Google as a sign-in provider.',
      );
    }

    // A null account means the user dismissed the picker — not an error.
    if (account == null) throw const AuthException('Sign-in was cancelled.');

    try {
      final auth = await account.authentication;
      if (auth.idToken == null && auth.accessToken == null) {
        throw const AuthException('Google sign-in returned no credential. Please try again.');
      }
      await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: auth.idToken, accessToken: auth.accessToken),
      );
    } on AuthException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageForCode(e.code));
    }

    await _exchangeFirebaseSession();
  }

  @override
  Future<void> signInWithApple() async {
    try {
      final provider = AppleAuthProvider()..addScope('email')..addScope('name');
      await _auth.signInWithProvider(provider);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageForCode(e.code));
    }
    await _exchangeFirebaseSession();
  }

  @override
  Future<void> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String phoneE164,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      await credential.user?.updateDisplayName('$firstName $lastName');
      // Re-read so the display name is populated on the instance the
      // exchange below reads from, rather than only on Firebase's servers.
      await credential.user?.reload();
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageForCode(e.code));
    }

    _pendingPhoneE164 = phoneE164;
    _pendingProfilePhone = phoneE164;

    // Provision the backend account *before* touching phone verification.
    // Phone OTP links an extra credential; it is not a precondition for a
    // usable account. Doing it the other way round meant a failed OTP send
    // aborted sign-up after the Firebase user already existed, leaving the
    // account half-created — and every retry then failed with
    // "email-already-in-use".
    await _exchangeFirebaseSession();

    phoneVerificationUnavailable = false;
    try {
      await _startPhoneVerification(phoneE164);
    } catch (error) {
      // Phone auth needs its provider enabled, a registered SHA-1 on Android,
      // and SMS quota. None of that should cost the user the account they
      // just created, so record it and let the OTP screen say so.
      debugPrint('Phone verification could not start: $error');
      phoneVerificationUnavailable = true;
    }
  }

  Future<void> _startPhoneVerification(String phoneE164) {
    final completer = Completer<void>();
    _auth.verifyPhoneNumber(
      phoneNumber: phoneE164,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (_) {
        // Android-only auto-retrieval; the OTP screen still drives the flow
        // explicitly, so there's nothing to do here beyond not erroring.
      },
      verificationFailed: (e) {
        if (!completer.isCompleted) completer.completeError(AuthException(_messageForCode(e.code)));
      },
      codeSent: (verificationId, resendToken) {
        _phoneVerificationId = verificationId;
        if (!completer.isCompleted) completer.complete();
      },
      codeAutoRetrievalTimeout: (verificationId) {
        _phoneVerificationId = verificationId;
      },
    );
    return completer.future;
  }

  @override
  Future<void> verifyOtp(String code) async {
    final verificationId = _phoneVerificationId;
    if (verificationId == null) {
      throw AuthException(
        phoneVerificationUnavailable
            // The account exists and works; only the optional phone link is
            // unavailable. Saying "expired" here would be misleading.
            ? "Phone verification isn't available for this build, so no code was sent. "
                  'Your account is already active — you can skip this step.'
            : 'Your verification session expired. Please request a new code.',
      );
    }
    try {
      final credential = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code);
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        await currentUser.linkWithCredential(credential);
      } else {
        await _auth.signInWithCredential(credential);
      }
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageForCode(e.code));
    }
  }

  @override
  Future<void> resendOtp() async {
    final phone = _pendingPhoneE164;
    if (phone == null) {
      throw const AuthException('Nothing to resend — start sign-up again.');
    }
    try {
      await _startPhoneVerification(phone);
      phoneVerificationUnavailable = false;
    } catch (error) {
      debugPrint('Phone verification resend failed: $error');
      phoneVerificationUnavailable = true;
      rethrow;
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (_) {
      // Deliberately swallowed: don't reveal whether an address has an
      // account, matching the mock implementation's behavior.
    }
  }

  @override
  Future<void> signOut() async {
    await _tokenStore.clearSession();
    await _auth.signOut();
    // Without this the native picker silently reuses the last account on the
    // next sign-in, so "sign out" wouldn't let the user switch accounts.
    try {
      // Lazily resolved, so this is also the first Google call in a session
      // that only ever used email sign-in — harmless, and still guarded.
      await _googleSignIn.signOut();
    } catch (_) {
      // Not signed in with Google, or the plugin is unavailable on this
      // platform — neither should block signing out.
    }
  }

  @override
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthException('No signed-in account to delete.');

    // Delete the backend record (and everything that cascades from it —
    // incidents, devices, contacts) first, while the JWT is still valid.
    // If this fails, stop here rather than deleting the Firebase identity
    // out from under a backend row that's still there — that would strand
    // the user's data with no way to sign back in and delete it properly.
    try {
      await _apiClient.dio.delete('/users/me');
    } catch (_) {
      throw const AuthException("Couldn't delete your account data. Check your connection and try again.");
    }

    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw const AuthException('For your security, please sign in again before deleting your account.');
      }
      throw AuthException(_messageForCode(e.code));
    }
    await _tokenStore.clearSession();
  }

  String _messageForCode(String code) {
    switch (code) {
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'weak-password':
        return 'Please choose a stronger password.';
      case 'invalid-verification-code':
        return 'Incorrect code. Please try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'operation-not-allowed':
        return 'This sign-in method isn\'t enabled for this app yet.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with the same email using a different sign-in method.';
      case 'popup-closed-by-user':
      case 'canceled':
      case 'web-context-cancelled':
        return 'Sign-in was cancelled.';
      case 'network-request-failed':
        return "Couldn't reach the server. Check your connection and try again.";
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
