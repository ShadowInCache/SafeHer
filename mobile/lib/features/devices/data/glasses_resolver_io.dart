import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';

import 'glasses_resolver.dart';

/// Native resolver: a real mDNS query, so `safeher-glasses.local` resolves on
/// Android where the OS will not do it.
GlassesAddressResolver createGlassesResolver() => MdnsGlassesResolver();

class MdnsGlassesResolver implements GlassesAddressResolver {
  MdnsGlassesResolver({MDnsClient Function()? clientFactory})
      : _clientFactory = clientFactory ?? MDnsClient.new;

  final MDnsClient Function() _clientFactory;
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
