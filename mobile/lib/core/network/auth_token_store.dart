import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the auth token used to authenticate API requests. Backed by
/// the platform keychain/keystore via [FlutterSecureStorage] rather than
/// Hive, since this is sensitive — never store it alongside ordinary app
/// state.
class AuthTokenStore {
  AuthTokenStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'safeher_auth_token';

  final FlutterSecureStorage _storage;

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);
}
