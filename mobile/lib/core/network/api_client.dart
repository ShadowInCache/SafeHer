import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'auth_token_store.dart';

/// Shared, pre-configured Dio instance for every `*RepositoryRemote`. Adds
/// the bearer token to outgoing requests, logs in debug builds only, and
/// leaves error mapping to [ApiException.fromDioException] at the call
/// site (repositories catch [DioException], not this client).
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
          ) {
    this.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokenStore.readToken();
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
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
  final AuthTokenStore _tokenStore;
}
