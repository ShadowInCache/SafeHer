import 'dart:convert';

/// Reads the account id out of a backend access token.
///
/// The offline queue has to know *whose* mutations it is holding. Nothing
/// else on the client carries a stable account identifier: `UserProfile` has
/// no id field, and the token store keeps only the tokens themselves. The
/// access token is a JWT whose `sub` claim is the user id (see
/// `TokenPayload` in `fastapi_app/schemas.py`), so that is the identifier
/// used here.
///
/// **This is not authentication.** The signature is deliberately not checked
/// and must never be trusted for access control — the server does that on
/// every request. All this provides is a local, stable key for answering
/// "did the account that queued this entry sign in again?", and a forged
/// token would only let an attacker replay their *own* queued entries.
///
/// Returns null for anything that is not a readable JWT, which callers must
/// treat as "owner unknown" rather than as a match.
String? accountIdFromAccessToken(String? accessToken) {
  if (accessToken == null || accessToken.isEmpty) return null;

  final segments = accessToken.split('.');
  if (segments.length < 2) return null;

  try {
    final payload = json.decode(
      utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
    );
    if (payload is! Map) return null;
    final sub = payload['sub'];
    return sub is String && sub.isNotEmpty ? sub : null;
  } catch (_) {
    // A malformed or opaque token is "owner unknown", never "owner matches".
    return null;
  }
}
