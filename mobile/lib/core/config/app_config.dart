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
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:5000/api/v1',
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

  static const apiConnectTimeout = Duration(seconds: 10);
  static const apiReceiveTimeout = Duration(seconds: 15);

  const AppConfig._();
}
