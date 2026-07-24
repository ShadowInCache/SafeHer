import 'package:uuid/uuid.dart';

import '../../../core/firebase/firebase_support.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/domain_models.dart';
import 'auth_repository.dart';

class HybridAuthRepository implements AuthRepository {
  final ApiClient _apiClient;
  final FirebaseSupport _firebaseSupport;
  final Uuid _uuid;

  @override
  final bool firebaseReady;

  HybridAuthRepository({
    required ApiClient apiClient,
    required FirebaseSupport firebaseSupport,
    required this.firebaseReady,
  }) : _apiClient = apiClient,
       _firebaseSupport = firebaseSupport,
       _uuid = const Uuid();

  @override
  Future<AuthSession> loginWithEmail({
    required String email,
    required String password,
    required AppRole role,
  }) async {
    if (firebaseReady) {
      await _firebaseSupport.signInWithEmail(email: email, password: password);
    }

    final jwt = await _issueToken(email: email, password: password);
    final user = await _fetchCurrentUser(fallbackRole: role, jwt: jwt);

    if (firebaseReady) {
      await _firebaseSupport.syncUserProfile(user);
      await _firebaseSupport.syncFcmToken(user.id);
      await _firebaseSupport.subscribeEmergencyTopic(user.id);
    }

    return AuthSession(user: user, jwt: jwt);
  }

  @override
  Future<AuthSession> signUpWithEmail({
    required String fullName,
    required String email,
    required String password,
    required String? phone,
    required AppRole role,
  }) async {
    if (firebaseReady) {
      await _firebaseSupport.createUserWithEmail(
        email: email,
        password: password,
      );
    }

    await _apiClient.post(
      '/auth/register',
      authenticated: false,
      body: {
        'email': email,
        'password': password,
        'full_name': fullName,
        'role': role.name,
      },
    );

    final jwt = await _issueToken(email: email, password: password);
    final user = await _fetchCurrentUser(fallbackRole: role, jwt: jwt);
    final hydratedUser = AppUser(
      id: user.id,
      fullName: user.fullName,
      email: user.email,
      role: user.role,
      phone: phone ?? user.phone,
    );

    if (firebaseReady) {
      await _firebaseSupport.syncUserProfile(hydratedUser);
      await _firebaseSupport.syncFcmToken(hydratedUser.id);
      await _firebaseSupport.subscribeEmergencyTopic(hydratedUser.id);
    }

    return AuthSession(user: hydratedUser, jwt: jwt);
  }

  @override
  Future<AuthSession> loginWithGoogle({required AppRole role}) async {
    if (!firebaseReady) {
      throw const ApiException(message: 'Google login requires Firebase setup');
    }

    final credential = await _firebaseSupport.signInWithGoogle();
    final firebaseUser = credential.user;
    if (firebaseUser == null) {
      throw const ApiException(
        message: 'Google login failed: no Firebase user returned',
      );
    }

    final idToken = await _firebaseSupport.getCurrentIdToken(
      forceRefresh: true,
    );
    final jwt = await _exchangeFirebaseToken(
      idToken: idToken,
      role: role,
      fullName: firebaseUser.displayName,
    );
    final user = await _fetchCurrentUser(fallbackRole: role, jwt: jwt);

    await _firebaseSupport.syncUserProfile(user);
    await _firebaseSupport.syncFcmToken(user.id);
    await _firebaseSupport.subscribeEmergencyTopic(user.id);

    return AuthSession(user: user, jwt: jwt);
  }

  @override
  Future<String> requestPhoneOtp(String phoneNumber) async {
    if (firebaseReady) {
      return _firebaseSupport.sendPhoneOtp(phoneNumber);
    }
    throw const ApiException(
      message: 'Phone OTP requires Firebase authentication to be configured.',
    );
  }

  @override
  Future<AuthSession> verifyPhoneOtp({
    required String verificationId,
    required String smsCode,
    required AppRole role,
  }) async {
    if (!firebaseReady) {
      throw const ApiException(
        message: 'Phone OTP requires Firebase authentication to be configured.',
      );
    }

    final credential = await _firebaseSupport.verifyOtp(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final firebaseUser = credential.user;
    if (firebaseUser == null) {
      throw const ApiException(
        message: 'OTP verification failed: no Firebase user returned.',
      );
    }

    final idToken = await _firebaseSupport.getCurrentIdToken(
      forceRefresh: true,
    );
    final jwt = await _exchangeFirebaseToken(
      idToken: idToken,
      role: role,
      fullName: firebaseUser.displayName,
    );

    final user = await _fetchCurrentUser(fallbackRole: role, jwt: jwt);
    await _firebaseSupport.syncUserProfile(user);
    await _firebaseSupport.syncFcmToken(user.id);
    await _firebaseSupport.subscribeEmergencyTopic(user.id);
    return AuthSession(user: user, jwt: jwt);
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    if (firebaseReady) {
      await _firebaseSupport.sendResetEmail(email);
    }
  }

  @override
  Future<void> logout() async {
    if (firebaseReady) {
      await _firebaseSupport.signOut();
    }
  }

  Future<String> _issueToken({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.post(
      '/auth/login',
      authenticated: false,
      body: {'email': email, 'password': password},
    );

    final token = response['access_token']?.toString();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'Authentication token missing from backend response.',
      );
    }

    return token;
  }

  Future<AppUser> _fetchCurrentUser({
    required AppRole fallbackRole,
    required String jwt,
  }) async {
    _apiClient.setAuthToken(jwt);
    final me = await _apiClient.get('/auth/me');
    return AppUser(
      id: (me['id'] ?? _uuid.v4()).toString(),
      fullName: (me['full_name'] ?? me['email'] ?? 'SafeHer User').toString(),
      email: (me['email'] ?? '').toString(),
      phone: me['phone']?.toString(),
      role: AppUser.fromJson({'role': me['role'] ?? fallbackRole.name}).role,
    );
  }

  Future<String> _exchangeFirebaseToken({
    required String idToken,
    required AppRole role,
    String? fullName,
  }) async {
    final response = await _apiClient.post(
      '/auth/firebase/exchange',
      authenticated: false,
      body: {
        'id_token': idToken,
        'role': role.name,
        if (fullName != null && fullName.trim().isNotEmpty)
          'full_name': fullName.trim(),
      },
    );

    final token = response['access_token']?.toString();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        message:
            'Authentication token missing from Firebase exchange response.',
      );
    }

    return token;
  }
}
