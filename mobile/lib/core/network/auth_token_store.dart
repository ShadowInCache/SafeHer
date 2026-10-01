import 'package:flutter/foundation.dart';
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

  /// The access token, or null when there isn't one that can be read.
  ///
  /// See [_readOrClear] for why "cannot be read" is folded into "absent".
  Future<String?> readToken() => _readOrClear(_accessTokenKey);

  Future<String?> readRefreshToken() => _readOrClear(_refreshTokenKey);

  /// Reads one key, treating an unreadable value as an absent one.
  ///
  /// **The failure this exists for.** `flutter_secure_storage` throws when the
  /// stored ciphertext cannot be decrypted with the current keystore key —
  /// `javax.crypto.BadPaddingException: BAD_DECRYPT`. That happens for entirely
  /// ordinary reasons: an app reinstall, a device-to-device restore, or an OS
  /// update that rotates the key. The bytes on disk are then permanently
  /// unreadable, and *every* caller of this class would throw, forever: the
  /// launch path's session check, the Dio interceptor that attaches the token
  /// to every authenticated request, the WebSocket handshake, and the offline
  /// queue's owner check.
  ///
  /// Observed on an Infinix X6832 (2026-10-01), where it left the app showing a
  /// blank dark screen on every launch: the splash's redirect is gated on the
  /// session check, the check threw, and the splash had already faded itself to
  /// invisible. Nothing on screen, nothing in the log.
  ///
  /// **Why deleting is right rather than merely convenient.** A token that
  /// cannot be decrypted is indistinguishable from no token: it cannot be sent,
  /// refreshed, or recovered, and either way the user has to sign in again. So
  /// the entry is removed and null returned, which makes the condition
  /// self-healing — the next successful sign-in writes fresh ciphertext under
  /// the current key and reads start working again. Keeping the corrupt bytes
  /// would mean throwing on every launch for the life of the install.
  ///
  /// It deliberately never rethrows. This is read on the path that decides
  /// whether the app can start at all, and a secure-storage fault must cost a
  /// sign-in, not the whole app.
  Future<String?> _readOrClear(String key) async {
    try {
      return await _storage.read(key: key);
    } on Object catch (error) {
      debugPrint('SafeHer: secure entry "$key" could not be read, clearing it: $error');
      try {
        await _storage.delete(key: key);
      } on Object catch (deleteError) {
        // If it will not delete either there is nothing further to try, and
        // null is still the honest answer: the caller must behave as though
        // there were no session, because for every practical purpose there
        // is not.
        debugPrint('SafeHer: secure entry "$key" could not be cleared: $deleteError');
      }
      return null;
    }
  }

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
