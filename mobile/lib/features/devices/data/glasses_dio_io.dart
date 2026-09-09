import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'glasses_resolver.dart';

/// A Dio that reaches the glasses on a network where the OS will not resolve
/// `safeher-glasses.local`.
///
/// The request URL keeps the hostname, so the release network-security policy
/// (which permits cleartext to that one name and no IP) still allows it and
/// the `Host:` header is unchanged. But the TCP socket opens to an address
/// this app resolved itself over mDNS, so Android's missing `.local` support
/// never enters into it. Who the request is *addressed* to and where the
/// bytes actually *go* are separated — the only way to satisfy both the
/// cleartext policy and a resolver that cannot see `.local`.
Dio glassesDio({
  required GlassesAddressResolver resolver,
  Duration timeout = const Duration(seconds: 3),
}) {
  final dio = Dio(BaseOptions(connectTimeout: timeout, receiveTimeout: timeout));

  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient()
        ..connectionTimeout = timeout
        ..connectionFactory = (uri, proxyHost, proxyPort) async {
          // A warm cache first; only look up when there is nothing to reuse.
          // A stale cached address surfaces as a failed connection, which the
          // caller clears and retries — not second-guessed here.
          final target =
              resolver.cachedAddress ?? await resolver.resolve(uri.host, timeout: timeout);
          // Null means nothing answered; fall back to the URL host so the OS
          // resolver still gets its attempt (iOS, or a real DNS record).
          return Socket.startConnect(target ?? uri.host, uri.port);
        };
      return client;
    },
  );

  return dio;
}
