import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/data/glasses_dio.dart';
import 'package:safeher_app/features/devices/data/glasses_resolver.dart';
import 'package:safeher_app/features/devices/data/glasses_resolver_io.dart';

/// A resolver with no network behind it: it maps the glasses name to whatever
/// address the test is standing a server on.
class _FixedResolver implements GlassesAddressResolver {
  _FixedResolver(this.address);
  final String? address;
  int calls = 0;

  @override
  String? get cachedAddress => null;

  @override
  void clearCache() {}

  @override
  Future<String?> resolve(String host, {Duration timeout = const Duration(seconds: 3)}) async {
    calls++;
    return address;
  }
}

void main() {
  group('glassesDio connection routing', () {
    late HttpServer server;
    late List<String?> hostHeaders;
    HttpOverrides? previousOverrides;

    setUp(() async {
      // flutter_test replaces networking with a stub that returns 400 for
      // everything, which would never reach the connectionFactory this test
      // is about. Restore real sockets for the duration, then put the stub
      // back so no other test is affected.
      previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      hostHeaders = [];
      // Loopback stands in for the glasses. The point of the test is that the
      // socket reaches *this* server while the URL still names the glasses.
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        hostHeaders.add(req.headers.value('host'));
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write('{"device":"safeher-glasses","firmware":"test"}');
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      HttpOverrides.global = previousOverrides;
    });

    test('routes the socket to the resolved address, keeping the .local host in the URL', () async {
      final resolver = _FixedResolver(server.address.address);
      final dio = glassesDio(resolver: resolver);

      // The URL names the glasses; only the resolver knows it is really
      // loopback. If the socket did not follow the resolver, this could not
      // connect at all.
      final response = await dio.getUri<Map<String, dynamic>>(
        Uri.parse('http://${GlassesAddressResolver.hostname}:${server.port}/status'),
      );

      expect(response.statusCode, 200);
      expect(response.data?['device'], 'safeher-glasses');

      // The release cleartext policy is keyed on this header/URL host. If the
      // client had rewritten the URL to the IP, the request would arrive with
      // an IP Host and a release build would have blocked it before sending.
      expect(hostHeaders.single, contains(GlassesAddressResolver.hostname));
    });

    test('falls back to the URL host when the resolver finds nothing', () async {
      // Resolver returns null (mDNS filtered, no multicast lock). The socket
      // should still try the URL host so the OS resolver -- which succeeds on
      // iOS and on networks with a real DNS record -- gets its own attempt.
      // Here the URL host is loopback, so it connects; the assertion is that
      // a null resolve does not abort the connection.
      final resolver = _FixedResolver(null);
      final dio = glassesDio(resolver: resolver);

      final response = await dio.getUri<Map<String, dynamic>>(
        Uri.parse('http://127.0.0.1:${server.port}/status'),
      );

      expect(response.statusCode, 200);
      expect(resolver.calls, greaterThan(0), reason: 'the resolver must be consulted');
    });
  });

  group('MdnsGlassesResolver without a network', () {
    test('a hand-typed IP is used as-is and cached, with no lookup', () async {
      final resolver = MdnsGlassesResolver();
      final ip = await resolver.resolve('192.168.1.50');

      expect(ip, '192.168.1.50');
      expect(resolver.cachedAddress, '192.168.1.50');
    });

    test('strips scheme, port and path before deciding', () async {
      final resolver = MdnsGlassesResolver();
      expect(await resolver.resolve('http://10.0.0.7:80/status'), '10.0.0.7');
    });

    test('a real DNS name is passed through untouched, not sent to mDNS', () async {
      // Only `.local` is ours to resolve; anything else the OS already handles,
      // so it returns immediately rather than waiting on a multicast timeout.
      final resolver = MdnsGlassesResolver();
      final result = await resolver
          .resolve('example.com')
          .timeout(const Duration(seconds: 1));
      expect(result, 'example.com');
    });

    test('clearCache forgets the last address', () async {
      final resolver = MdnsGlassesResolver();
      await resolver.resolve('192.168.1.50');
      resolver.clearCache();
      expect(resolver.cachedAddress, isNull);
    });
  });
}
