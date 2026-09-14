library;

/// Resolves [glassesDio] to the implementation this platform can run: the
/// mDNS-steering client on native, a plain client on web. The native half
/// needs `dart:io`, which throws on web, so it is reached only through this
/// conditional export. See `glasses_dio_io.dart`.
export 'glasses_dio_stub.dart' if (dart.library.io) 'glasses_dio_io.dart';