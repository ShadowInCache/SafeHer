import 'package:dio/dio.dart';

/// Typed, user-safe error surfaced by [ApiClient] in place of a raw
/// [DioException] — repository implementations catch [DioException] and
/// rethrow this, so callers (and the UI's `AsyncValue.error` branches)
/// never need to know Dio exists.
class ApiException implements Exception {
  const ApiException({required this.message, this.statusCode});

  final String message;
  final int? statusCode;

  factory ApiException.fromDioException(DioException error) {
    switch (error.type) {
      // Failing to *reach* the server and the server failing to *answer* are
      // different faults with different remedies, and telling someone to check
      // a working connection sends them to fix the wrong thing. The backend
      // hibernates when idle and takes about a minute to wake, which surfaces
      // here as a receive timeout after a handshake that succeeded instantly.
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        return const ApiException(
          message: 'Could not reach the server in time. Check your network and try again.',
        );
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException(
          message: 'The server is taking longer than usual to reply — it may be '
              'waking up. Give it a moment and try again.',
        );
      case DioExceptionType.connectionError:
        return const ApiException(message: "Couldn't reach the server. Check your connection and try again.");
      case DioExceptionType.badCertificate:
        return const ApiException(message: 'Could not verify the server. Please try again later.');
      case DioExceptionType.cancel:
        return const ApiException(message: 'The request was cancelled.');
      case DioExceptionType.badResponse:
        return ApiException(
          message: _messageForStatus(error.response?.statusCode),
          statusCode: error.response?.statusCode,
        );
      case DioExceptionType.unknown:
        return const ApiException(message: 'Something went wrong. Please try again.');
    }
  }

  static String _messageForStatus(int? statusCode) {
    if (statusCode == 401) return 'Your session has expired. Please sign in again.';
    if (statusCode == 403) return "You don't have permission to do that.";
    if (statusCode == 404) return "That couldn't be found.";
    if (statusCode != null && statusCode >= 500) return 'The server had a problem. Please try again shortly.';
    return 'Something went wrong. Please try again.';
  }

  @override
  String toString() => message;
}
