/// Central switch between the mock repository implementations (used for
/// every screen built so far) and real network-backed ones.
///
/// There is no live SafeHer backend yet, so [useMockApi] defaults to
/// true and the app behaves exactly as it did before Phase 4 — every
/// repository provider still returns its `*RepositoryMock`. Once a real
/// API exists: set [apiBaseUrl], flip [useMockApi] to false (or better,
/// thread it through `--dart-define`), and each repository provider will
/// switch to its `*RepositoryRemote` implementation without any other
/// code changing, since both implement the same domain interface.
abstract final class AppConfig {
  static const useMockApi = bool.fromEnvironment('USE_MOCK_API', defaultValue: true);

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.safeher.example.com/v1',
  );

  static const apiConnectTimeout = Duration(seconds: 10);
  static const apiReceiveTimeout = Duration(seconds: 15);

  const AppConfig._();
}
