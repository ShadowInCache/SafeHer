import 'glasses_resolver.dart';

/// Web build: there is no raw-socket mDNS in a browser, so this resolves
/// nothing and lets the request go out with its original host. A browser
/// either resolves `.local` itself (some do) or it does not; either way this
/// compiles and never throws, which `dart:io` would.
GlassesAddressResolver createGlassesResolver() => const WebGlassesResolver();

class WebGlassesResolver implements GlassesAddressResolver {
  const WebGlassesResolver();

  @override
  String? get cachedAddress => null;

  @override
  void clearCache() {}

  @override
  Future<String?> resolve(String host, {Duration timeout = const Duration(seconds: 3)}) async => null;
}
