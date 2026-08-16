import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/network/api_exception.dart';
import 'package:safeher_app/features/auth/domain/auth_repository.dart';
import 'package:safeher_app/shared/utils/user_error.dart';

DioException _badResponse(int statusCode, {Object? data}) {
  final options = RequestOptions(path: '/dashboard/analytics');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: statusCode, data: data),
  );
}

void main() {
  group('describeError', () {
    test('an unknown endpoint reads as an outdated server, not a missing record', () {
      // FastAPI answers an unknown route with the generic {"detail": "Not
      // Found"}. Rendering that as "that couldn't be found" sent a real
      // debugging session after a contact that existed perfectly well; the
      // truth was a backend nobody had restarted.
      final failure = describeError(_badResponse(404, data: {'detail': 'Not Found'}));

      expect(failure.title, 'Server needs updating');
      expect(failure.message.toLowerCase(), contains('restart the backend'));
    });

    test('a missing record still reads as a missing record', () {
      final failure = describeError(_badResponse(404, data: {'detail': 'Contact not found'}));

      expect(failure.title, 'Not available');
      expect(failure.message.toLowerCase(), isNot(contains('restart the backend')));
    });

    test('a 404 is not blamed on the network', () {
      // This is the case that cost real debugging time: a backend older
      // than the app 404s the new route, and the screen told the user to
      // check a connection that was working perfectly.
      final failure = describeError(_badResponse(404, data: {'detail': 'Contact not found'}));

      expect(failure.title, 'Not available');
      expect(failure.message.toLowerCase(), isNot(contains('connection')));
    });

    test('a genuine connection failure does say so', () {
      final failure = describeError(
        DioException(
          requestOptions: RequestOptions(path: '/dashboard/analytics'),
          type: DioExceptionType.connectionError,
        ),
      );

      expect(failure.message.toLowerCase(), contains('connection'));
    });

    test('distinguishes an expired session from a server fault', () {
      expect(describeError(_badResponse(401)).title, 'Session expired');
      expect(describeError(_badResponse(500)).title, 'Server problem');
      expect(describeError(_badResponse(403)).title, 'Not allowed');
    });

    test('passes an ApiException through with its own message', () {
      final failure = describeError(
        const ApiException(message: 'That device is already paired.', statusCode: 409),
      );

      expect(failure.message, 'That device is already paired.');
    });

    test('keeps an auth message verbatim under the caller’s headline', () {
      final failure = describeError(
        const AuthException('Incorrect email or password.'),
        fallbackTitle: 'Couldn’t sign you in',
      );

      expect(failure.title, 'Couldn’t sign you in');
      expect(failure.message, 'Incorrect email or password.');
    });

    test('never renders a raw object at the user', () {
      // The screens used to call error.toString() directly, which prints
      // "Instance of '_Exception'" for anything without an override.
      final failure = describeError(Exception('kaboom'));

      expect(failure.message, isNot(contains('Instance of')));
      expect(failure.message, isNot(contains('kaboom')));
      expect(failure.message, contains('try again'));
    });

    test('handles a null error without throwing', () {
      expect(describeError(null).title, 'Something went wrong');
    });
  });
}
