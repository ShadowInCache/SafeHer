import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/network/api_client.dart';
import 'package:safeher_app/core/network/auth_token_store.dart';
import 'package:safeher_app/features/auth/data/auth_repository_native.dart';
import 'package:safeher_app/features/auth/domain/auth_repository.dart';

/// Replays canned backend responses and records what was sent.
///
/// The shapes below mirror `fastapi_app/routers/auth.py`; the contract tests in
/// `tests/test_auth_security.py` pin the server side of the same exchange.
class _FakeBackend implements ApiClient {
  _FakeBackend();

  final List<({String method, String path, Object? data})> requests = [];

  /// path -> (status, body). Consumed in order when a path is queued twice.
  final Map<String, List<(int, Map<String, dynamic>)>> responses = {};

  void stub(String path, int status, Map<String, dynamic> body) =>
      (responses[path] ??= []).add((status, body));

  @override
  late final Dio dio = Dio()
    ..options.baseUrl = 'http://localhost/api/v1'
    ..httpClientAdapter = _Adapter(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.backend);

  final _FakeBackend backend;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    backend.requests.add((method: options.method, path: options.path, data: options.data));

    final queued = backend.responses[options.path];
    if (queued == null || queued.isEmpty) {
      return ResponseBody.fromString(jsonEncode({'detail': 'not stubbed'}), 404, headers: _json);
    }
    final (status, body) = queued.removeAt(0);
    return ResponseBody.fromString(jsonEncode(body), status, headers: _json);
  }

  static const _json = {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  };

  @override
  void close({bool force = false}) {}
}

class _InMemoryTokenStore implements AuthTokenStore {
  BackendSession? session;

  @override
  Future<void> saveSession(BackendSession value) async => session = value;

  @override
  Future<String?> readToken() async => session?.accessToken;

  @override
  Future<String?> readRefreshToken() async => session?.refreshToken;

  @override
  Future<void> clearSession() async => session = null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _tokens() => {
  'access_token': 'backend-jwt',
  'refresh_token': 'backend-refresh',
  'token_type': 'bearer',
};

void main() {
  late _FakeBackend backend;
  late _InMemoryTokenStore store;
  late AuthRepositoryNative repo;

  setUp(() {
    backend = _FakeBackend();
    store = _InMemoryTokenStore();
    repo = AuthRepositoryNative(apiClient: backend, tokenStore: store);
  });

  Future<void> signUp() => repo.signUp(
    firstName: 'Asha',
    lastName: 'Rao',
    email: 'asha@example.com',
    phoneE164: '+919876543210',
    password: 'TestPass123!',
  );

  group('sign-up', () {
    test('signs the user straight in when verification is not required', () async {
      backend.stub('/auth/register', 201, {
        'user': {'id': 'u1', 'email': 'asha@example.com'},
        'verification_required': false,
        'verification_sent': false,
      });
      backend.stub('/auth/login', 200, _tokens());

      await signUp();

      expect(
        store.session?.accessToken,
        'backend-jwt',
        reason: 'sign-up must leave the user signed in, not stranded on a login screen',
      );
      expect(backend.requests.map((r) => r.path), ['/auth/register', '/auth/login']);
    });

    test('sends the profile fields the backend persists', () async {
      backend.stub('/auth/register', 201, {
        'user': {'id': 'u1'},
        'verification_required': false,
        'verification_sent': false,
      });
      backend.stub('/auth/login', 200, _tokens());

      await signUp();

      final body = backend.requests.first.data as Map;
      expect(body['email'], 'asha@example.com');
      expect(body['password'], 'TestPass123!');
      expect(body['full_name'], 'Asha Rao', reason: 'first and last name are joined for the API');
      expect(body['phone'], '+919876543210');
    });

    test('holds the session back until the emailed code is confirmed', () async {
      backend.stub('/auth/register', 201, {
        'user': {'id': 'u1'},
        'verification_required': true,
        'verification_sent': true,
      });

      await signUp();

      expect(store.session, isNull, reason: 'an unverified account must not get a session');
      expect(backend.requests.length, 1, reason: 'no login attempt before verification');
      expect(repo.phoneVerificationUnavailable, isFalse);
    });

    test('flags undeliverable codes so the OTP screen can say so', () async {
      backend.stub('/auth/register', 201, {
        'user': {'id': 'u1'},
        'verification_required': true,
        'verification_sent': false,
      });

      await signUp();

      expect(
        repo.phoneVerificationUnavailable,
        isTrue,
        reason: 'the user must not be left waiting for mail that was never sent',
      );
    });

    test('surfaces the backend message for a duplicate address', () async {
      backend.stub('/auth/register', 400, {'detail': 'User already exists'});

      await expectLater(
        signUp(),
        throwsA(isA<AuthException>().having((e) => e.message, 'message', 'User already exists')),
      );
    });
  });

  group('sign-in', () {
    test('stores the returned session', () async {
      backend.stub('/auth/login', 200, _tokens());

      await repo.signInWithEmail(email: 'asha@example.com', password: 'TestPass123!');

      expect(store.session?.accessToken, 'backend-jwt');
      expect(store.session?.refreshToken, 'backend-refresh');
      expect(await repo.hasActiveSession(), isTrue);
    });

    test('passes the lockout wait through verbatim', () async {
      backend.stub('/auth/login', 429, {
        'detail': 'Too many failed sign-in attempts. Try again in 15 minutes.',
      });

      await expectLater(
        repo.signInWithEmail(email: 'asha@example.com', password: 'nope'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('15 minutes'),
            // The server already computes the remaining wait; restating it in
            // the client would risk showing a different number.
          ),
        ),
      );
    });

    test('explains an unreachable backend rather than blaming credentials', () async {
      final offline = _FakeBackend();
      offline.dio.httpClientAdapter = _OfflineAdapter();
      final offlineRepo = AuthRepositoryNative(apiClient: offline, tokenStore: store);

      await expectLater(
        offlineRepo.signInWithEmail(email: 'asha@example.com', password: 'TestPass123!'),
        throwsA(isA<AuthException>().having((e) => e.message, 'message', contains('Cannot reach'))),
      );
    });
  });

  group('email verification', () {
    test('verifying the code establishes the session', () async {
      backend.stub('/auth/register', 201, {
        'user': {'id': 'u1'},
        'verification_required': true,
        'verification_sent': true,
      });
      backend.stub('/auth/verify-email', 200, _tokens());

      await signUp();
      await repo.verifyOtp('123456');

      expect(store.session?.accessToken, 'backend-jwt');
      final body = backend.requests.last.data as Map;
      expect(body['email'], 'asha@example.com', reason: 'the pending address is reused');
      expect(body['code'], '123456');
    });

    test('refuses to verify with no pending address', () async {
      await expectLater(repo.verifyOtp('123456'), throwsA(isA<AuthException>()));
      expect(backend.requests, isEmpty);
    });

    test('resend updates the delivery flag', () async {
      backend.stub('/auth/register', 201, {
        'user': {'id': 'u1'},
        'verification_required': true,
        'verification_sent': false,
      });
      backend.stub('/auth/resend-verification', 202, {
        'status': 'accepted',
        'verification_sent': true,
      });

      await signUp();
      expect(repo.phoneVerificationUnavailable, isTrue);

      await repo.resendOtp();
      expect(repo.phoneVerificationUnavailable, isFalse);
    });
  });

  group('federated sign-in', () {
    test('Google explains the console requirement instead of failing opaquely', () async {
      await expectLater(
        repo.signInWithGoogle(),
        throwsA(
          isA<AuthException>().having((e) => e.message, 'message', contains('Firebase Authentication')),
        ),
      );
      expect(backend.requests, isEmpty);
    });

    test('Apple explains the console requirement', () async {
      await expectLater(repo.signInWithApple(), throwsA(isA<AuthException>()));
    });
  });

  group('session teardown', () {
    test('sign-out clears the local session even when the server call fails', () async {
      backend.stub('/auth/login', 200, _tokens());
      await repo.signInWithEmail(email: 'asha@example.com', password: 'TestPass123!');
      // `/auth/logout` is deliberately left unstubbed, so it 404s.

      await repo.signOut();

      expect(
        store.session,
        isNull,
        reason: 'a failed server logout must still sign the user out on this device',
      );
    });

    test('account deletion clears the session', () async {
      backend.stub('/auth/login', 200, _tokens());
      await repo.signInWithEmail(email: 'asha@example.com', password: 'TestPass123!');
      backend.stub('/auth/account', 200, {
        'deletion_requested_at': '2026-08-14T00:00:00',
        'purge_scheduled_for': '2026-09-13T00:00:00',
        'grace_period_days': 30,
      });

      await repo.deleteAccount();

      expect(store.session, isNull);
      expect(backend.requests.last.method, 'DELETE');
    });
  });

  group('password reset', () {
    test('requests a reset code for the address', () async {
      backend.stub('/auth/password-reset/request', 202, {
        'status': 'accepted',
        'code_sent': true,
      });

      await repo.sendPasswordResetEmail('asha@example.com');

      expect(backend.requests.single.path, '/auth/password-reset/request');
      expect((backend.requests.single.data as Map)['email'], 'asha@example.com');
    });
  });
}

class _OfflineAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
  }

  @override
  void close({bool force = false}) {}
}
