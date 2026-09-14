library;

/// Resolves [createGlassesResolver] to the implementation this platform can
/// run: the mDNS resolver on native, a no-op on web. See `glasses_resolver.dart`.
export 'glasses_resolver_stub.dart'
    if (dart.library.io) 'glasses_resolver_io.dart';