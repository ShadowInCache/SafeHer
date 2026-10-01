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
    test('maps a failure to reach the server to a network message', () {
      // Nothing got through, so the user's own connection is the first thing
      // worth checking.
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
      ]) {
        final exception = ApiException.fromDioException(_dioError(type));
        expect(exception.message, contains('Could not reach the server'), reason: '$type');
        expect(exception.message.toLowerCase(), contains('network'), reason: '$type');
      }
    });

    test('maps a server that does not answer to a waking message', () {
      // Deliberately *not* the same message as above. The backend hibernates
      // when idle and takes about a minute to wake, which lands here: the
      // handshake succeeds instantly and then nothing comes back. Telling
      // someone to check a connection that demonstrably works sends them to
      // fix the wrong thing — and this was the message shown while sign-in
      // was impossible, which is how the cause stayed hidden.
      for (final type in [
        DioExceptionType.receiveTimeout,
        DioExceptionType.transformTimeout,
      ]) {
        final exception = ApiException.fromDioException(_dioError(type));
        expect(exception.message, contains('waking up'), reason: '$type');
        expect(
          exception.message.toLowerCase(),
          isNot(contains('check your network')),
          reason: '$type must not blame a connection that just completed a handshake',
        );
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
