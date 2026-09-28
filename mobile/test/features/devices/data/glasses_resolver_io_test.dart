@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:safeher_app/features/devices/data/glasses_resolver_io.dart';
import 'package:safeher_app/features/devices/data/multicast_lock.dart';

/// The resolver's job is to turn `safeher-glasses.local` into an address on a
/// platform whose OS will not. The lock is the part that was missing: without
/// it the query is sent and the reply is filtered out by the Wi-Fi chip, which
/// looks exactly like a camera that is switched off.
void main() {
  group('the multicast lock is held around the query', () {
    test('acquired before the client starts, released after it stops', () async {
      final events = <String>[];
      final resolver = MdnsGlassesResolver(
        clientFactory: () => _FakeMDnsClient(events),
        lock: _RecordingLock(events),
      );

      final result = await resolver.resolve('safeher-glasses.local');

      expect(result, isNull, reason: 'the fake client answers nothing');
      expect(events, ['acquire', 'start', 'stop', 'release']);
    });

    test('released even when the client throws', () async {
      final events = <String>[];
      final resolver = MdnsGlassesResolver(
        clientFactory: () => _FakeMDnsClient(events, failOnStart: true),
        lock: _RecordingLock(events),
      );

      expect(await resolver.resolve('safeher-glasses.local'), isNull);
      expect(events.last, 'release', reason: 'a leaked lock drains the battery');
    });

    test('a lock that cannot be taken still lets the query run', () async {
      // Emulators and phones with no Wi-Fi service report false. On a network
      // that does not filter multicast the lookup works regardless, so
      // refusing to try would break a setup that works today.
      final events = <String>[];
      final resolver = MdnsGlassesResolver(
        clientFactory: () => _FakeMDnsClient(events),
        lock: _RecordingLock(events, acquires: false),
      );

      expect(await resolver.resolve('safeher-glasses.local'), isNull);
      expect(events, ['acquire', 'start', 'stop']);
    });
  });

  group('addresses that need no multicast do not take the lock', () {
    test('a hand-typed IP is returned as itself', () async {
      final events = <String>[];
      final resolver = MdnsGlassesResolver(
        clientFactory: () => _FakeMDnsClient(events),
        lock: _RecordingLock(events),
      );

      expect(await resolver.resolve('192.168.1.42'), '192.168.1.42');
      expect(resolver.cachedAddress, '192.168.1.42');
      expect(events, isEmpty);
    });

    test('a non-.local name is left to the OS resolver', () async {
      final events = <String>[];
      final resolver = MdnsGlassesResolver(
        clientFactory: () => _FakeMDnsClient(events),
        lock: _RecordingLock(events),
      );

      expect(await resolver.resolve('camera.lan'), 'camera.lan');
      expect(events, isEmpty);
    });

    test('scheme, port and path are stripped before the lookup', () async {
      final events = <String>[];
      final resolver = MdnsGlassesResolver(
        clientFactory: () => _FakeMDnsClient(events),
        lock: _RecordingLock(events),
      );

      expect(await resolver.resolve('http://192.168.1.42:81/stream'), '192.168.1.42');
    });
  });
}

class _RecordingLock extends MulticastLock {
  _RecordingLock(this.events, {this.acquires = true});

  final List<String> events;
  final bool acquires;

  @override
  Future<bool> acquire() async {
    events.add('acquire');
    return acquires;
  }

  @override
  Future<void> release() async => events.add('release');
}

/// Answers nothing, which is what a filtered network looks like from Dart.
/// `noSuchMethod` covers the rest of `MDnsClient`'s surface so this does not
/// have to be rewritten every time that package adds a member.
class _FakeMDnsClient implements MDnsClient {
  _FakeMDnsClient(this.events, {this.failOnStart = false});

  final List<String> events;
  final bool failOnStart;

  @override
  Future<void> start({
    InternetAddress? listenAddress,
    Future<Iterable<NetworkInterface>> Function(InternetAddressType)? interfacesFactory,
    int mDnsPort = 5353,
    InternetAddress? mDnsAddress,
    Function? onError,
  }) async {
    events.add('start');
    if (failOnStart) throw StateError('no multicast interface');
  }

  @override
  Stream<T> lookup<T extends ResourceRecord>(
    ResourceRecordQuery query, {
    Duration timeout = const Duration(seconds: 5),
  }) =>
      const Stream.empty();

  @override
  void stop() => events.add('stop');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
