/// Controls whether repositories bind to mock (fixture) data or real
/// Dio/Firebase-backed implementations. No backend exists yet, so this
/// defaults to mock; flip via --dart-define=SAFEHER_FLAVOR=prod once the
/// API integration layer (Phase 4) lands.
abstract final class AppFlavor {
  static const _flavor = String.fromEnvironment('SAFEHER_FLAVOR', defaultValue: 'mock');

  static bool get isMock => _flavor != 'prod';

  const AppFlavor._();
}
