import 'dart:io';

import 'package:flutter/foundation.dart';

/// Builds the datagram socket `multicast_dns` sends its queries from, pinned to
/// the WiFi interface.
///
/// The package binds one socket to `anyIPv4` (its `start()` asserts on anything
/// else) and joins the multicast group on every interface, so *receiving* is
/// already correct. Sending is not: with mobile data and WiFi up at once, a
/// datagram to `224.0.0.251` has no specific route, so the kernel sends it via
/// whichever network Android has made the default — normally cellular, and
/// especially when the WiFi has no internet. The query leaves over the modem
/// and the camera never hears it, while unicast HTTP to the camera works fine,
/// because an RFC1918 address does have a route over WiFi.
///
/// That is the failure this fixes, and it is a different one from the multicast
/// lock: the lock governs whether replies survive the Wi-Fi chip's filter, this
/// governs which interface the question leaves by. Both are required.
///
/// `IP_MULTICAST_IF` is set on this socket alone. Android's
/// `ConnectivityManager.bindProcessToNetwork` would also work and is the
/// documented way to force a network, but it binds *every* socket in the
/// process — so an SOS raised during the few seconds of a lookup could try to
/// reach the API over a WiFi link with no internet. Not a trade worth making in
/// this app.
Future<RawDatagramSocket> mdnsSocketFactory(
  dynamic host,
  int port, {
  bool reuseAddress = true,
  bool reusePort = true,
  int ttl = 255,
}) async {
  final socket = await RawDatagramSocket.bind(
    host,
    port,
    reuseAddress: reuseAddress,
    reusePort: reusePort,
    ttl: ttl,
  );

  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final chosen = selectMulticastInterface(interfaces);
    if (chosen != null) {
      final address = chosen.addresses.firstWhere(
        (candidate) => candidate.type == InternetAddressType.IPv4,
      );
      socket.setRawOption(
        RawSocketOption(
          RawSocketOption.levelIPv4,
          ipMulticastIf,
          Uint8List.fromList(address.rawAddress),
        ),
      );
    }
  } on Object catch (error) {
    // Never fatal. On a phone with only WiFi up, the default route is already
    // right and the lookup succeeds without this.
    if (kDebugMode) debugPrint('mDNS: could not pin multicast interface: $error');
  }

  return socket;
}

/// `IP_MULTICAST_IF` on Linux, and therefore on Android.
@visibleForTesting
const int ipMulticastIf = 32;

/// Picks the interface an mDNS query should leave by: the WiFi one.
///
/// Named prefixes rather than anything cleverer, because Dart exposes no
/// transport type for an interface. `wlan0` is WiFi on Android; `rmnet`,
/// `ccmni` and `pdp` are the mobile radio on the common chipsets, and
/// `v4-rmnet`/`clat` are the NAT64 shims sitting on top of it. Anything
/// unrecognised is a last resort rather than a first choice, so a phone whose
/// WiFi interface has an unexpected name still gets something usable instead of
/// nothing.
@visibleForTesting
NetworkInterface? selectMulticastInterface(Iterable<NetworkInterface> interfaces) {
  NetworkInterface? fallback;

  for (final interface in interfaces) {
    final hasUsableAddress = interface.addresses.any(
      (address) => address.type == InternetAddressType.IPv4 && !address.isLoopback,
    );
    if (!hasUsableAddress) continue;

    final name = interface.name.toLowerCase();
    if (_isLoopback(name) || _isCellular(name)) continue;
    if (_isWifi(name)) return interface;
    fallback ??= interface;
  }

  return fallback;
}

bool _isWifi(String name) =>
    name.startsWith('wlan') || name.startsWith('wl') || name.startsWith('ap');

bool _isCellular(String name) =>
    name.startsWith('rmnet') ||
    name.startsWith('v4-rmnet') ||
    name.startsWith('ccmni') ||
    name.startsWith('pdp') ||
    name.startsWith('clat') ||
    name.startsWith('rmnet_data');

bool _isLoopback(String name) => name.startsWith('lo');
