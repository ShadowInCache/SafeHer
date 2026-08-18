/// Central switch between the mock repository implementations (fixture
/// data, no network) and real network-backed ones.
///
/// Every feature now has a real `fastapi_app` path — auth, contacts,
/// emergency dispatch, devices, the dashboard, reports, live monitoring
/// (WebSocket), BLE pairing, and settings — so [useMockApi] defaults to
/// false: a plain `flutter run` talks to the real local backend (see repo
/// root SETUP.md for `python app.py`). Pass
/// `--dart-define=USE_MOCK_API=true` to explore the UI on fixture data
/// without running the backend at all.
abstract final class AppConfig {
  static const useMockApi = bool.fromEnvironment('USE_MOCK_API', defaultValue: false);

  /// Defaults to the local dev `fastapi_app` backend (see repo root
  /// SETUP.md) reachable from a desktop/web build on the same machine.
  /// Android emulators can't resolve `127.0.0.1` back to the host — pass
  /// `--dart-define=API_BASE_URL=http://10.0.2.2:5000/api/v1` there
  /// instead; a physical device needs the host's LAN IP.
  ///
  /// The default is the deployed backend, not localhost. A release build that
  /// falls back to `127.0.0.1` is one that silently cannot work on a user's
  /// phone, and the failure looks like a network problem rather than a
  /// misbuild. Development overrides it with `--dart-define`.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://safeher-sf68.onrender.com/api/v1',
  );

  /// Whether sign-in goes through Firebase Auth.
  ///
  /// Defaults to true: Authentication is enabled on the `safeher-2a1f2` project
  /// (Google, Phone and Anonymous providers), and Firebase is the only path that
  /// can serve federated sign-in, phone OTP and guest mode. Every successful
  /// Firebase sign-in is still exchanged for a `fastapi_app` JWT, so the backend
  /// remains the owner of the account.
  ///
  /// Pass `--dart-define=USE_FIREBASE_AUTH=false` to fall back to
  /// backend-native email/password auth, which needs no console configuration.
  /// That path cannot do Google, Apple or guest sign-in.
  static const useFirebaseAuth = bool.fromEnvironment('USE_FIREBASE_AUTH', defaultValue: true);

  /// Comma-separated, base64-encoded SHA-256 fingerprints of the DER
  /// certificates the API is allowed to present (SRS section 5.2). Supplied
  /// at build time with `--dart-define=PINNED_CERT_SHA256=<pin>,<backup>`
  /// and never committed -- a pin is not a secret, but hardcoding one turns
  /// certificate renewal into a source release.
  ///
  /// Empty in development, where the backend is plain HTTP on localhost and
  /// there is no certificate to pin. See `certificate_pinning.dart` for how
  /// to read a fingerprint off a live host, and why you want two of them.
  static const _pinnedCertificateHashesRaw = String.fromEnvironment('PINNED_CERT_SHA256');

  static Set<String> get pinnedCertificateHashes => _splitPins(_pinnedCertificateHashesRaw);

  /// Issuers the API's certificate is allowed to come from, as they appear in
  /// `X509Certificate.issuer`. Supplied with
  /// `--dart-define=PINNED_CERT_ISSUERS=<issuer>[,<issuer>]`.
  ///
  /// This exists because leaf pinning is the wrong tool for a certificate the
  /// hosting platform manages. Render serves a Google Trust Services
  /// certificate for `onrender.com` that it renews roughly every ninety days,
  /// and a leaf pin would stop matching the moment it rotated — every
  /// installed copy of SafeHer would lose the backend, mid-emergency for
  /// anyone unlucky, with no fix but a store update. On a safety app that is
  /// a worse outcome than the attack pinning defends against.
  ///
  /// Pinning the issuer survives renewal, because the intermediate is stable
  /// for years, while still refusing a certificate minted by any *other*
  /// authority — which is exactly the corporate-MDM or hostile-WiFi CA that
  /// SRS section 5.2 has in mind.
  ///
  /// Prefer [pinnedCertificateHashes] once the API moves to a custom domain
  /// whose certificate you control and can rotate deliberately.
  /// Defaults to the authority that issues the certificate for
  /// [apiBaseUrl]'s host. The two defaults describe one deployment and have
  /// to move together: overriding `API_BASE_URL` to a host with a different
  /// CA without also overriding this would refuse every connection.
  ///
  /// Defaulting rather than requiring a `--dart-define` is deliberate. A pin
  /// that must be remembered at build time is a pin that ships missing, and
  /// SRS section 5.2 asks for pinning in release builds — not for pinning in
  /// the release builds somebody remembered to configure.
  static const _pinnedCertificateIssuersRaw = String.fromEnvironment(
    'PINNED_CERT_ISSUERS',
    defaultValue: 'O=Google Trust Services',
  );

  static Set<String> get pinnedCertificateIssuers =>
      _splitPins(_pinnedCertificateIssuersRaw);

  static Set<String> _splitPins(String raw) => raw
      .split(',')
      .map((pin) => pin.trim())
      .where((pin) => pin.isNotEmpty)
      .toSet();

  /// The national emergency number the SOS screen offers to call.
  ///
  /// 112 is India's single emergency number (ERSS), which routes to police,
  /// fire and ambulance. Overridable per build for other countries, because
  /// a hardcoded 112 shown to someone in the UK or the US would be a wrong
  /// number at the worst possible moment.
  static const emergencyHelplineNumber = String.fromEnvironment(
    'EMERGENCY_HELPLINE',
    defaultValue: '112',
  );

  static const apiConnectTimeout = Duration(seconds: 10);
  static const apiReceiveTimeout = Duration(seconds: 15);

  const AppConfig._();
}
