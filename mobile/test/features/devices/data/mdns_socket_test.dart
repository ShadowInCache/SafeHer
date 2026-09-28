@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/data/mdns_socket_io.dart';

/// Which interface an mDNS query leaves by decides whether the camera ever
/// hears it. On a phone with mobile data and WiFi up at once, the default route
/// is the modem, and a query sent that way is simply lost — while unicast to
/// the camera keeps working, which is what makes the failure so confusing.
void main() {
  group('selectMulticastInterface', () {
    test('prefers WiFi over the cellular interface', () {
      // The real case: Android keeps cellular as the default network when the
      // WiFi has no internet, so route order cannot be trusted here.
      final chosen = selectMulticastInterface([
        _Interface('rmnet_data0', ['10.66.1.20']),
        _Interface('wlan0', ['10.66.78.42']),
      ]);

      expect(chosen?.name, 'wlan0');
    });

    test('picks WiFi even when the cellular interface is listed first and last', () {
      final chosen = selectMulticastInterface([
        _Interface('rmnet_data0', ['10.0.0.2']),
        _Interface('wlan0', ['192.168.1.5']),
        _Interface('v4-rmnet_data0', ['192.0.0.4']),
      ]);

      expect(chosen?.name, 'wlan0');
    });

    test('never picks a NAT64 shim sitting on the modem', () {
      // clat/v4-rmnet carry a private-looking IPv4 address, so an "is it
      // RFC1918" test would happily choose one of these and send the query
      // out over cellular anyway.
      final chosen = selectMulticastInterface([
        _Interface('clat4', ['192.0.0.4']),
        _Interface('v4-rmnet_data2', ['192.0.0.6']),
      ]);

      expect(chosen, isNull);
    });

    test('ignores loopback', () {
      expect(selectMulticastInterface([_Interface('lo', ['127.0.0.1'])]), isNull);
    });

    test('ignores an interface with no usable IPv4 address', () {
      expect(selectMulticastInterface([_Interface('wlan0', [])]), isNull);
    });

    test('falls back to an unrecognised interface rather than giving up', () {
      // A phone whose WiFi interface is not called wlan0 still gets something
      // usable; returning null would leave the query on the default route.
      final chosen = selectMulticastInterface([
        _Interface('rmnet_data0', ['10.0.0.2']),
        _Interface('eth7', ['192.168.8.9']),
      ]);

      expect(chosen?.name, 'eth7');
    });

    test('a recognised WiFi name still beats an unrecognised one', () {
      final chosen = selectMulticastInterface([
        _Interface('eth7', ['192.168.8.9']),
        _Interface('wlan0', ['192.168.1.5']),
      ]);

      expect(chosen?.name, 'wlan0');
    });

    test('no interfaces at all is not an error', () {
      expect(selectMulticastInterface(const []), isNull);
    });
  });

  group('the socket option', () {
    test('IP_MULTICAST_IF is the Linux value', () {
      // Android is Linux; 32 is what the kernel expects. A wrong constant here
      // fails silently -- setRawOption succeeds and the query still leaves by
      // the default route.
      expect(ipMulticastIf, 32);
    });
  });
}

class _Interface implements NetworkInterface {
  _Interface(this.name, List<String> addresses)
      : addresses = addresses.map(InternetAddress.new).toList();

  @override
  final String name;

  @override
  final List<InternetAddress> addresses;

  @override
  int get index => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
