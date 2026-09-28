import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';

import 'glasses_resolver.dart';
import 'mdns_socket_io.dart';
import 'multicast_lock.dart';

/// Native resolver: a real mDNS query, so `safeher-glasses.local` resolves on
/// Android where the OS will not do it.
GlassesAddressResolver createGlassesResolver() => MdnsGlassesResolver();

class MdnsGlassesResolver implements GlassesAddressResolver {
  MdnsGlassesResolver({
    MDnsClient Function()? clientFactory,
    MulticastLock lock = const MulticastLock(),
  })  : _clientFactory = clientFactory ?? _defaultClient,
        _lock = lock;

  /// A client whose queries leave by the WiFi interface rather than by
  /// whichever network Android has made the default — see [mdnsSocketFactory].
  static MDnsClient _defaultClient() =>
      MDnsClient(rawDatagramSocketFactory: mdnsSocketFactory);

  final MDnsClient Function() _clientFactory;

  /// Held for the duration of the query. Without it Android's Wi-Fi chip
  /// discards the reply before Dart ever sees it — see [MulticastLock].
  final MulticastLock _lock;
  String? _cached;

  @override
  String? get cachedAddress => _cached;

  @override
  void clearCache() => _cached = null;

  @override
  Future<String?> resolve(
    String host, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final bare = _bareHost(host);

    if (_looksLikeIp(bare)) {
      _cached = bare;
      return bare;
    }
    if (!bare.endsWith('.local')) return bare;

    // The lock wraps the whole query, including client startup: the reply can
    // arrive within milliseconds of the question going out.
    return _lock.hold(() => _lookup(bare, timeout));
  }

  Future<String?> _lookup(String bare, Duration timeout) async {
    final client = _clientFactory();
    try {
      await client.start();
      final query = ResourceRecordQuery.addressIPv4(bare);
      await for (final IPAddressResourceRecord record
          in client.lookup<IPAddressResourceRecord>(query).timeout(
        timeout,
        onTimeout: (sink) => sink.close(),
      )) {
        final ip = record.address.address;
        _cached = ip;
        return ip;
      }
    } on TimeoutException {
      // Multicast filtered, or no Android multicast lock. The caller turns a
      // null into a message that offers the manual-IP path.
    } catch (error) {
      if (kDebugMode) debugPrint('mDNS lookup for $bare failed: $error');
    } finally {
      client.stop();
    }
    return null;
  }

  static String _bareHost(String host) {
    var value = host.trim();
    if (value.startsWith('http://')) value = value.substring(7);
    if (value.startsWith('https://')) value = value.substring(8);
    final slash = value.indexOf('/');
    if (slash != -1) value = value.substring(0, slash);
    final colon = value.indexOf(':');
    if (colon != -1) value = value.substring(0, colon);
    return value;
  }

  static bool _looksLikeIp(String value) => InternetAddress.tryParse(value) != null;
}
