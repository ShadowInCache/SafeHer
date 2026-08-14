import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/network/api_client.dart';
import 'package:safeher_app/core/network/auth_token_store.dart';
import 'package:safeher_app/features/auth/data/auth_repository_remote.dart';

/// Captures what the app posts to `/auth/firebase/exchange` without touching
/// the network.
class _RecordingApiClient implements ApiClient {
  final List<({String path, Object? data})> posts = [];

  @override
  late final Dio dio = Dio()
    ..httpClientAdapter = _StubAdapter(this)
    ..options.baseUrl = 'http://localhost/api/v1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.client);

  final _RecordingApiClient client;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    client.posts.add((path: options.path, data: options.data));
    return ResponseBody.fromString(
      '{"access_token":"backend-jwt","refresh_token":"backend-refresh"}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

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

void main() {
  group('AuthRepositoryRemote session state', () {
    late _InMemoryTokenStore store;

    setUp(() => store = _InMemoryTokenStore());

    test('hasActiveSession reflects the backend JWT, not Firebase', () async {
      final repo = AuthRepositoryRemote(
        apiClient: _RecordingApiClient(),
        tokenStore: store,
      );

      expect(await repo.hasActiveSession(), isFalse);

      await store.saveSession(const BackendSession(accessToken: 'jwt', refreshToken: null));
      expect(
        await repo.hasActiveSession(),
        isTrue,
        reason: 'every other repository needs the backend JWT, so that is the source of truth',
      );
    });

    test('phone verification is assumed available until proven otherwise', () {
      final repo = AuthRepositoryRemote(
        apiClient: _RecordingApiClient(),
        tokenStore: store,
      );
      expect(repo.phoneVerificationUnavailable, isFalse);
    });
  });
}
