import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'glasses_resolver.dart';
import 'glasses_resolver_platform.dart';

/// One resolver for the whole app, so its address cache is shared: pairing
/// warms it, and the MJPEG stream reuses it instead of running a fresh
/// multicast query on every reconnect.
final glassesResolverProvider = Provider<GlassesAddressResolver>(
  (ref) => createGlassesResolver(),
);
