import 'package:dio/dio.dart';

import '../../core/network/api_exception.dart';
import '../../features/auth/domain/auth_repository.dart';

/// A failure phrased for the person holding the phone: a short headline and
/// one sentence saying what to do about it.
class UserError {
  const UserError({required this.title, required this.message});

  final String title;
  final String message;
}

/// Turns any thrown object into a [UserError].
///
/// This exists because the screens used to render `error.toString()`
/// directly. For an [AuthException] that happens to read well; for a
/// [DioException] it puts a stack-shaped string in front of a user, and for
/// anything else it prints `Instance of '...'`. Worse, the fixed copy some
/// screens used ("Check your connection and try again") accused the network
/// of failures it had nothing to do with — a 404 from a backend that had not
/// been restarted sent exactly that message, and it cost real debugging time.
UserError describeError(Object? error, {String fallbackTitle = 'Something went wrong'}) {
  if (error is DioException && _isUnknownEndpoint(error)) return _outdatedServer;
  if (error is ApiException) {
    return UserError(title: _titleForStatus(error.statusCode, fallbackTitle), message: error.message);
  }
  if (error is DioException) {
    final api = ApiException.fromDioException(error);
    return UserError(title: _titleForStatus(api.statusCode, fallbackTitle), message: api.message);
  }
  if (error is AuthException) {
    return UserError(title: fallbackTitle, message: error.message);
  }
  return UserError(
    title: fallbackTitle,
    message: 'Please try again. If it keeps happening, restart the app.',
  );
}

/// A 404 has two very different meanings and the app kept conflating them.
///
/// FastAPI answers an unknown *route* with the generic `{"detail": "Not
/// Found"}`; every handler in this project answers a missing *record* with
/// something specific ("Contact not found"). Telling a user "that couldn't
/// be found" when the truth is "this server is older than your app" sends
/// her looking for a record that was never the problem — which has now cost
/// three separate debugging sessions, all of them ending at a backend
/// nobody had restarted.
bool _isUnknownEndpoint(DioException error) {
  if (error.response?.statusCode != 404) return false;
  final data = error.response?.data;
  final detail = data is Map ? data['detail'] : null;
  return detail == null || detail.toString().trim().toLowerCase() == 'not found';
}

const _outdatedServer = UserError(
  title: 'Server needs updating',
  message: 'This feature is missing from the server you are connected to. '
      'If you are running SafeHer locally, restart the backend.',
);

String _titleForStatus(int? statusCode, String fallback) {
  if (statusCode == null) return fallback;
  if (statusCode == 401) return 'Session expired';
  if (statusCode == 403) return 'Not allowed';
  // Distinguished from a network failure on purpose: a 404 means we reached
  // the server and it had no such route — usually a backend that is older
  // than the app. Telling the user to check their connection would send them
  // after the wrong problem.
  if (statusCode == 404) return 'Not available';
  if (statusCode >= 500) return 'Server problem';
  return fallback;
}
