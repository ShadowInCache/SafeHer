import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../firebase_options.dart';
import '../../shared/models/domain_models.dart';

class FirebaseSupport {
  bool _ready = false;

  bool get isReady => _ready;

  Future<bool> initialize() async {
    if (_ready) {
      return true;
    }

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _ready = true;
      return true;
    } catch (_) {
      _ready = false;
      return false;
    }
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) {
    return FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserCredential> createUserWithEmail({
    required String email,
    required String password,
  }) {
    return FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserCredential> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      throw StateError('Google sign in cancelled');
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    return FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<void> sendResetEmail(String email) {
    return FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  }

  Future<String> sendPhoneOtp(String phoneNumber) {
    final completer = Completer<String>();

    FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (credential) async {
        await FirebaseAuth.instance.signInWithCredential(credential);
      },
      verificationFailed: (error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      codeSent: (verificationId, _) {
        if (!completer.isCompleted) {
          completer.complete(verificationId);
        }
      },
      codeAutoRetrievalTimeout: (verificationId) {
        if (!completer.isCompleted) {
          completer.complete(verificationId);
        }
      },
    );

    return completer.future;
  }

  Future<UserCredential> verifyOtp({
    required String verificationId,
    required String smsCode,
  }) {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<String> getCurrentIdToken({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('No Firebase user is currently signed in');
    }

    final token = await user.getIdToken(forceRefresh);
    if (token == null || token.isEmpty) {
      throw StateError('Firebase ID token is unavailable');
    }

    return token;
  }

  Future<void> syncUserProfile(AppUser user) async {
    await FirebaseFirestore.instance.collection('users').doc(user.id).set({
      ...user.toJson(),
      'updated_at': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> syncFcmToken(String userId) async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) {
      return;
    }

    await FirebaseFirestore.instance.collection('fcm_tokens').doc(userId).set({
      'token': token,
      'updated_at': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> subscribeEmergencyTopic(String userId) {
    return FirebaseMessaging.instance.subscribeToTopic('safeher_$userId');
  }

  Future<void> logNonFatal(Object error, StackTrace stackTrace) async {
    await FirebaseCrashlytics.instance.recordError(error, stackTrace);
  }

  Future<void> signOut() {
    return FirebaseAuth.instance.signOut();
  }
}
