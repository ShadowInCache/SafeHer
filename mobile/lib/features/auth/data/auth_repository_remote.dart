import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../domain/auth_repository.dart';

/// Firebase Auth-backed [AuthRepository]. Email/password sign-in, sign-up,
/// and password reset map directly onto FirebaseAuth's own methods; the
/// OTP screen maps onto Firebase's phone-number verification flow —
/// [signUp] kicks it off via [FirebaseAuth.verifyPhoneNumber] and
/// [verifyOtp] completes it with the resulting verification ID.
class AuthRepositoryRemote implements AuthRepository {
  AuthRepositoryRemote({FirebaseAuth? firebaseAuth}) : _auth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;
  String? _phoneVerificationId;
  String? _pendingPhoneE164;

  @override
  Future<bool> hasActiveSession() async {
    return _auth.currentUser != null;
  }

  @override
  Future<void> signInWithEmail({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageForCode(e.code));
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
    try {
      final credential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      await credential.user?.updateDisplayName('$firstName $lastName');
      _pendingPhoneE164 = phoneE164;
      await _startPhoneVerification(phoneE164);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageForCode(e.code));
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
      throw const AuthException('Your verification session expired. Please request a new code.');
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
    await _startPhoneVerification(phone);
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
      case 'network-request-failed':
        return "Couldn't reach the server. Check your connection and try again.";
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
