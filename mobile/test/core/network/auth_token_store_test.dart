import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/network/auth_token_store.dart';

/// A keystore that cannot decrypt what it previously stored.
///
/// This is not a hypothetical. `flutter_secure_storage` throws exactly this
/// when the Android keystore key the ciphertext was written under no longer
/// matches — after a reinstall, a device-to-device restore, or an OS update.
/// Captured from an Infinix X6832 on 2026-10-01, where it left the app on a
/// blank dark screen at every launch.
class _UndecryptableStorage extends FlutterSecureStorage {
  _UndecryptableStorage({this.deleteAlsoFails = false});

  final bool deleteAlsoFails;
  final List<String> deleted = <String>[];
  int reads = 0;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    reads++;
    throw PlatformException(
      code: 'Exception encountered',
      message: 'read',
      details: 'javax.crypto.BadPaddingException: '
          'error:1e000065:Cipher functions:OPENSSL_internal:BAD_DECRYPT',
    );
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (deleteAlsoFails) {
      throw PlatformException(code: 'Exception encountered', message: 'delete');
    }
    deleted.add(key);
  }
}

/// A keystore that works, so the fault handling cannot quietly swallow a real
/// session.
class _HealthyStorage extends FlutterSecureStorage {
  _HealthyStorage(this.values);

  final Map<String, String> values;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      values[key];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a token that cannot be decrypted', () {
    test('reads as absent rather than throwing', () async {
      // The whole point. This is read on the path that decides whether the app
      // can start: the splash awaits it before redirecting, and a throw there
      // left the user on a blank dark screen with the splash already faded to
      // invisible. A secure-storage fault must cost a sign-in, not the app.
      final storage = _UndecryptableStorage();

      await expectLater(AuthTokenStore(storage: storage).readToken(), completion(isNull));
      expect(storage.reads, 1);
    });

    test('is cleared, so the next launch is not broken the same way', () async {
      // Undecryptable bytes stay undecryptable. Leaving them would mean
      // throwing on every launch for the life of the install; removing them
      // makes the next successful sign-in repair the condition.
      final storage = _UndecryptableStorage();

      await AuthTokenStore(storage: storage).readToken();

      expect(storage.deleted, ['safeher_access_token']);
    });

    test('still reads as absent when it cannot even be cleared', () async {
      // Nothing further can be tried, and null remains the honest answer: for
      // every practical purpose there is no session.
      final storage = _UndecryptableStorage(deleteAlsoFails: true);

      await expectLater(AuthTokenStore(storage: storage).readToken(), completion(isNull));
    });

    test('the refresh token is treated the same way', () async {
      // It is read on the 401 retry path, so an unreadable one would turn a
      // recoverable token refresh into a thrown exception mid-request.
      final storage = _UndecryptableStorage();

      await expectLater(
        AuthTokenStore(storage: storage).readRefreshToken(),
        completion(isNull),
      );
      expect(storage.deleted, ['safeher_refresh_token']);
    });
  });

  group('a working keystore is untouched', () {
    test('returns the stored access token', () async {
      final store = AuthTokenStore(
        storage: _HealthyStorage({'safeher_access_token': 'jwt-abc'}),
      );

      expect(await store.readToken(), 'jwt-abc');
    });

    test('a genuinely empty store still reads as null', () async {
      // Absent and unreadable both produce null, which is correct — but this
      // pins that the fault path is not the only way to get there.
      final store = AuthTokenStore(storage: _HealthyStorage({}));

      expect(await store.readToken(), isNull);
    });
  });
}
