import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/network/api_exception.dart';

DioException _dioError(DioExceptionType type, {int? statusCode}) {
  final requestOptions = RequestOptions(path: '/test');
  return DioException(
    requestOptions: requestOptions,
    type: type,
    response: statusCode != null ? Response(requestOptions: requestOptions, statusCode: statusCode) : null,
  );
}

void main() {
  group('ApiException.fromDioException', () {
    test('maps timeout types to a network message', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        final exception = ApiException.fromDioException(_dioError(type));
        expect(exception.message, contains('timed out'));
      }
    });

    test('maps connection errors to a reachability message', () {
      final exception = ApiException.fromDioException(_dioError(DioExceptionType.connectionError));
      expect(exception.message, contains("Couldn't reach the server"));
    });

    test('maps 401 to a session-expired message', () {
      final exception = ApiException.fromDioException(_dioError(DioExceptionType.badResponse, statusCode: 401));
      expect(exception.statusCode, 401);
      expect(exception.message, contains('session has expired'));
    });

    test('maps 404 to a not-found message', () {
      final exception = ApiException.fromDioException(_dioError(DioExceptionType.badResponse, statusCode: 404));
      expect(exception.message, contains("couldn't be found"));
    });

    test('maps 500+ to a server-error message', () {
      final exception = ApiException.fromDioException(_dioError(DioExceptionType.badResponse, statusCode: 503));
      expect(exception.message, contains('server had a problem'));
    });

    test('toString returns the message', () {
      const exception = ApiException(message: 'custom message');
      expect(exception.toString(), 'custom message');
    });
  });
}
