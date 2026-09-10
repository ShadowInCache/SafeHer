/// Turns `safeher-glasses.local` into an address the socket layer can reach.
///
/// The glasses advertise over mDNS as `safeher-glasses.local`. iOS resolves
/// `.local` natively; Android does not, and neither does its HTTP stack —
/// which is why the browser shows "this site can't be reached" and why
/// pairing timed out on Android while working on iOS.
///
/// This is the platform-neutral contract. The native implementation
/// (`MdnsGlassesResolver`) lives in `glasses_resolver_io.dart` and is reached
/// only through `glasses_resolver_platform.dart`'s conditional export, because
/// mDNS needs `dart:io` sockets that throw on web. The web build gets a stub
/// that resolves nothing, since a browser cannot open raw sockets anyway.
abstract class GlassesAddressResolver {
  /// The mDNS name the glasses advertise, without scheme or path.
  static const hostname = 'safeher-glasses.local';

  /// Resolves [host] to an IPv4 address, or null if nothing answers inside
  /// [timeout]. A hand-typed IP is returned as itself; a non-`.local` name is
  /// left to the OS resolver.
  Future<String?> resolve(String host, {Duration timeout});

  /// The last address that answered, so an MJPEG reconnect does not pay for a
  /// fresh multicast round trip. Null before the first success.
  String? get cachedAddress;

  /// Forgotten on unpair, so a different camera later is not reached at the
  /// old one's address.
  void clearCache();
}
