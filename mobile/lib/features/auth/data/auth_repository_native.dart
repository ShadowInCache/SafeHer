import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/auth_token_store.dart';
import '../domain/auth_repository.dart';

/// Email/password auth handled entirely by `fastapi_app`, with no Firebase.
///
/// [AuthRepositoryRemote] routes sign-up through Firebase Auth and then
/// exchanges the resulting ID token for a backend JWT. That works only once the
/// Firebase console has the Authentication product enabled — until then
/// `identitytoolkit` answers `CONFIGURATION_NOT_FOUND` and no account can be
/// created at all, no matter what the app does.
///
/// This implementation removes that dependency for the flows the backend can
/// serve by itself (SRS FR-AUTH-01 email/password, FR-AUTH-04 JWT sessions,
/// FR-AUTH-06 password change, FR-AUTH-08 deletion). Federated sign-in
/// (FR-AUTH-02 Google, FR-AUTH-03 Apple) genuinely requires an identity
/// provider, so those throw a message naming the console step rather than
/// pretending to work.
class AuthRepositoryNative implements AuthRepository {
  AuthRepositoryNative({required ApiClient apiClient, required AuthTokenStore tokenStore})
    : _apiClient = apiClient,
      _tokenStore = tokenStore;

  final ApiClient _apiClient;
  final AuthTokenStore _tokenStore;

  /// The address awaiting an emailed OTP, remembered between the sign-up call
  /// and the OTP screen so the user does not have to retype it.
  String? _pendingEmail;

  /// Set when the backend reports it could not actually send the code (no SMTP
  /// configured). The OTP screen uses this to explain the situation instead of
  /// leaving the user waiting for mail that will never arrive.
  bool _verificationDeliveryFailed = false;

  /// Verification is an email step here, not a phone one. The interface member
  /// is named for the Firebase implementation's phone OTP; for this repository
  /// it answers the same question the OTP screen asks — "is the code actually
  /// coming?" — so the screen can offer a way forward either way.
  @override
  bool get phoneVerificationUnavailable => _verificationDeliveryFailed;

  @override
  Future<bool> hasActiveSession() async => await _tokenStore.readToken() != null;

  @override
  Future<void> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String phoneE164,
    required String password,
  }) async {
    final fullName = [firstName, lastName].where((part) => part.trim().isNotEmpty).join(' ').trim();

    final response = await _post('/auth/register', {
      'email': email,
      'password': password,
      if (fullName.isNotEmpty) 'full_name': fullName,
      if (phoneE164.trim().isNotEmpty) 'phone': phoneE164,
    });

    final body = _asMap(response.data);
    final verificationRequired = body['verification_required'] == true;
    _pendingEmail = email;
    _verificationDeliveryFailed = verificationRequired && body['verification_sent'] != true;

    if (verificationRequired) {
      // The account exists but cannot be used until the OTP is entered, so no
      // session is stored here. The OTP screen calls [verifyOtp] next.
      return;
    }

    // Verification is not enforced, so sign the user straight in — otherwise
    // sign-up would appear to succeed and leave them on a login screen.
    await signInWithEmail(email: email, password: password);
  }

  @override
  Future<void> signInWithEmail({required String email, required String password}) async {
    final response = await _post('/auth/login', {'email': email, 'password': password});
    await _storeSession(response.data);
    _pendingEmail = email;
  }

  @override
  Future<void> verifyOtp(String code) async {
    final email = _pendingEmail;
    if (email == null) {
      throw const AuthException('Start again from sign-up or sign-in to request a new code.');
    }
    final response = await _post('/auth/verify-email', {'email': email, 'code': code});
    await _storeSession(response.data);
  }

  @override
  Future<void> resendOtp() async {
    final email = _pendingEmail;
    if (email == null) {
      throw const AuthException('Start again from sign-up or sign-in to request a new code.');
    }
    final response = await _post('/auth/resend-verification', {'email': email});
    _verificationDeliveryFailed = _asMap(response.data)['verification_sent'] != true;
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    await _post('/auth/password-reset/request', {'email': email});
    _pendingEmail = email;
  }

  @override
  Future<void> signInAsGuest() async {
    // Anonymous identity is issued by Firebase; `fastapi_app` has no equivalent
    // and inventing a local one would create an account nothing could recover.
    throw const AuthException(
      'Guest mode needs Firebase Authentication enabled for this project. '
      'Use email and password, or see SETUP.md section 4b.',
    );
  }

  @override
  Future<void> signInWithGoogle() async {
    throw const AuthException(
      'Google sign-in needs Firebase Authentication enabled for this project. '
      'Use email and password, or see SETUP.md section 4b.',
    );
  }

  @override
  Future<void> signInWithApple() async {
    throw const AuthException(
      'Apple sign-in needs Firebase Authentication enabled for this project. '
      'Use email and password, or see SETUP.md section 4b.',
    );
  }

  @override
  Future<void> signOut() async {
    // Clear the local session first: if the server call fails, the user must
    // still end up signed out on this device rather than stuck signed in.
    await _tokenStore.clearSession();
    _pendingEmail = null;
    _verificationDeliveryFailed = false;
    try {
      await _apiClient.dio.post<dynamic>('/auth/logout');
    } on DioException {
      // Already signed out locally; the token expires on its own.
    }
  }

  @override
  Future<void> deleteAccount() async {
    try {
      await _apiClient.dio.delete<dynamic>('/auth/account');
    } on DioException catch (error) {
      throw AuthException(_messageFor(error));
    }
    await _tokenStore.clearSession();
    _pendingEmail = null;
  }

  // ------------------------------------------------------------------ helpers

  Future<Response<dynamic>> _post(String path, Map<String, dynamic> body) async {
    try {
      return await _apiClient.dio.post<dynamic>(path, data: body);
    } on DioException catch (error) {
      throw AuthException(_messageFor(error));
    }
  }

  Future<void> _storeSession(dynamic data) async {
    final body = _asMap(data);
    final accessToken = body['access_token'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw const AuthException('Sign-in did not return a session. Please try again.');
    }
    await _tokenStore.saveSession(
      BackendSession(
        accessToken: accessToken,
        refreshToken: body['refresh_token'] is String ? body['refresh_token'] as String : null,
      ),
    );
  }

  static Map<String, dynamic> _asMap(dynamic data) =>
      data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};

  /// Turns a Dio failure into something worth showing a user.
  ///
  /// The backend already writes user-facing text into `detail` (lockout waits,
  /// expired codes), so that is preferred over anything invented here.
  static String _messageFor(DioException error) {
    final detail = _asMap(error.response?.data)['detail'];
    if (detail is String && detail.isNotEmpty) return detail;

    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Cannot reach SafeHer. Check your connection and try again.';
      default:
        break;
    }

    final status = error.response?.statusCode;
    if (status == 401) return 'Incorrect email or password.';
    if (status == 409 || status == 400) return 'That email is already registered.';
    return 'Something went wrong. Please try again.';
  }
}
