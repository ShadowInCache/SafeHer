import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The access/refresh token pair returned by every `fastapi_app` auth
/// endpoint (`/auth/register`+`/login`, `/auth/firebase/exchange`,
/// `/auth/refresh`) — see repo root API.md.
class BackendSession {
  const BackendSession({required this.accessToken, this.refreshToken});

  final String accessToken;
  final String? refreshToken;
}

/// Persists the backend JWT pair used to authenticate every `fastapi_app`
/// request. Backed by the platform keychain/keystore via
/// [FlutterSecureStorage] rather than Hive, since this is sensitive — never
/// store it alongside ordinary app state.
class AuthTokenStore {
  AuthTokenStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _accessTokenKey = 'safeher_access_token';
  static const _refreshTokenKey = 'safeher_refresh_token';

  final FlutterSecureStorage _storage;

  Future<String?> readToken() => _storage.read(key: _accessTokenKey);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> saveSession(BackendSession session) async {
    await _storage.write(key: _accessTokenKey, value: session.accessToken);
    if (session.refreshToken != null) {
      await _storage.write(key: _refreshTokenKey, value: session.refreshToken);
    }
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}
