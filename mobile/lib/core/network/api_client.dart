import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'auth_token_store.dart';

/// Shared, pre-configured Dio instance for every `*RepositoryRemote`. Adds
/// the bearer token to outgoing requests, silently refreshes it once on a
/// 401 (matching FR-AUTH-04: silent refresh, no UX disruption) and logs in
/// debug builds only. Error mapping is left to
/// [ApiException.fromDioException] at the call site (repositories catch
/// [DioException], not this client).
class ApiClient {
  ApiClient({required AuthTokenStore tokenStore, Dio? dio})
    : _tokenStore = tokenStore,
      dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.apiBaseUrl,
              connectTimeout: AppConfig.apiConnectTimeout,
              receiveTimeout: AppConfig.apiReceiveTimeout,
              headers: {'Content-Type': 'application/json'},
            ),
          ),
      _refreshDio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: AppConfig.apiConnectTimeout,
          receiveTimeout: AppConfig.apiReceiveTimeout,
          headers: {'Content-Type': 'application/json'},
        ),
      ) {
    this.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokenStore.readToken();
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
        onError: (error, handler) async {
          final isUnauthorized = error.response?.statusCode == 401;
          final alreadyRetried = error.requestOptions.extra['safeherRetried'] == true;
          if (!isUnauthorized || alreadyRetried) return handler.next(error);

          final refreshed = await _tryRefresh();
          if (!refreshed) return handler.next(error);

          try {
            final retryOptions = error.requestOptions;
            retryOptions.extra['safeherRetried'] = true;
            final newToken = await _tokenStore.readToken();
            if (newToken != null) retryOptions.headers['Authorization'] = 'Bearer $newToken';
            final response = await this.dio.fetch(retryOptions);
            handler.resolve(response);
          } on DioException catch (retryError) {
            handler.next(retryError);
          }
        },
      ),
    );
    if (kDebugMode) {
      this.dio.interceptors.add(
        LogInterceptor(requestBody: true, responseBody: true, error: true),
      );
    }
  }

  final Dio dio;
  final Dio _refreshDio;
  final AuthTokenStore _tokenStore;

  /// Attempts one silent refresh via `POST /auth/refresh`. Clears the
  /// stored session on any failure so the caller's original 401 propagates
  /// as a real "please sign in again" rather than looping.
  Future<bool> _tryRefresh() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null) return false;
    try {
      final response = await _refreshDio.post('/auth/refresh', data: {'refresh_token': refreshToken});
      final newAccessToken = response.data['access_token'] as String?;
      final newRefreshToken = response.data['refresh_token'] as String?;
      if (newAccessToken == null) return false;
      await _tokenStore.saveSession(
        BackendSession(accessToken: newAccessToken, refreshToken: newRefreshToken),
      );
      return true;
    } on DioException {
      await _tokenStore.clearSession();
      return false;
    }
  }
}
