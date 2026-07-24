import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  static const String jwtKey = 'safeher_jwt';
  static const String refreshTokenKey = 'safeher_refresh';
  static const String userIdKey = 'safeher_user_id';
  static const String encryptionKey = 'safeher_aes_key';

  final FlutterSecureStorage _storage;

  SecureStore()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );

  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  Future<String?> read(String key) {
    return _storage.read(key: key);
  }

  Future<void> delete(String key) {
    return _storage.delete(key: key);
  }

  Future<void> clearAuth() async {
    await delete(jwtKey);
    await delete(refreshTokenKey);
    await delete(userIdKey);
  }
}
