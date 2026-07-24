import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_environment.dart';
import '../services/secure_store.dart';
import 'api_exception.dart';

class ApiClient {
  final AppEnvironment environment;
  final SecureStore secureStore;
  final http.Client _http;

  ApiClient({
    required this.environment,
    required this.secureStore,
    http.Client? client,
  }) : _http = client ?? http.Client();

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    final uri = Uri.parse(
      '${environment.apiBaseUrl}$path',
    ).replace(queryParameters: query);
    final response = await _requestWithRetry(
      () => _http.get(uri, headers: _buildHeaders(authenticated)),
    );
    return _decodeAsMap(response);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    final uri = Uri.parse('${environment.apiBaseUrl}$path');
    final response = await _requestWithRetry(
      () => _http.post(
        uri,
        headers: _buildHeaders(authenticated),
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return _decodeAsMap(response);
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    final uri = Uri.parse('${environment.apiBaseUrl}$path');
    final response = await _requestWithRetry(
      () => _http.put(
        uri,
        headers: _buildHeaders(authenticated),
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return _decodeAsMap(response);
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    bool authenticated = true,
  }) async {
    final uri = Uri.parse('${environment.apiBaseUrl}$path');
    final response = await _requestWithRetry(
      () => _http.delete(uri, headers: _buildHeaders(authenticated)),
    );
    return _decodeAsMap(response);
  }

  Map<String, String> _buildHeaders(bool authenticated) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (authenticated && _cachedJwt != null && _cachedJwt!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_cachedJwt';
    }

    return headers;
  }

  String? get authToken => _cachedJwt;

  void setAuthToken(String token) {
    _cachedJwt = token;
  }

  Map<String, String> get authenticatedJsonHeaders {
    if (_cachedJwt == null || _cachedJwt!.isEmpty) {
      throw const ApiException(message: 'Missing authentication token');
    }
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $_cachedJwt',
    };
  }

  String? _cachedJwt;

  Future<void> refreshAuthHeaderFromStore() async {
    _cachedJwt = await secureStore.read(SecureStore.jwtKey);
  }

  Future<http.Response> _requestWithRetry(
    Future<http.Response> Function() operation,
  ) async {
    const maxAttempts = 3;
    var attempt = 0;

    while (true) {
      attempt++;
      try {
        final response = await operation().timeout(const Duration(seconds: 20));
        if (response.statusCode >= 500 && attempt < maxAttempts) {
          await Future.delayed(Duration(milliseconds: 350 * attempt));
          continue;
        }

        return response;
      } on TimeoutException {
        if (attempt >= maxAttempts) {
          throw const ApiException(message: 'Request timeout');
        }
        await Future.delayed(Duration(milliseconds: 350 * attempt));
      } on ApiException {
        rethrow;
      } catch (error) {
        if (attempt >= maxAttempts) {
          throw ApiException(message: 'Network failure: $error');
        }
        await Future.delayed(Duration(milliseconds: 350 * attempt));
      }
    }
  }

  Map<String, dynamic> _decodeAsMap(http.Response response) {
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw ApiException(
        message: _extractError(response.body),
        statusCode: response.statusCode,
      );
    }

    if (response.body.trim().isEmpty) {
      return {};
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    return {'data': decoded};
  }

  String _extractError(String body) {
    if (body.isEmpty) {
      return 'Unknown API failure';
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return (decoded['message'] ?? decoded['detail'] ?? 'API failure')
            .toString();
      }
    } catch (_) {
      // Ignore parse failures and return raw body.
    }

    return body;
  }
}
