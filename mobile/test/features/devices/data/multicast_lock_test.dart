import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/data/multicast_lock.dart';

/// Android drops multicast replies unless this lock is held, so an mDNS query
/// for `safeher-glasses.local` goes out and the answer is discarded below
/// Dart. These pin the two things that matter: the lock is actually taken
/// around the query, and no failure to take it ever stops the query running.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.github.akshayag.safeher/multicast');
  final calls = <String>[];
  late MulticastLock lock;

  void mockNative({Object? acquireReturns = true, Object? throws}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (throws != null) throw throws;
      return call.method == 'acquire' ? acquireReturns : null;
    });
  }

  setUp(() {
    calls.clear();
    lock = const MulticastLock();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('hold', () {
    test('acquires before the body and releases after it', () async {
      mockNative();
      final order = <String>[];

      final result = await lock.hold(() async {
        order.add('body');
        return 42;
      });

      expect(result, 42);
      expect(calls, ['acquire', 'release']);
      expect(order, ['body']);
    });

    test('releases even when the lookup throws', () async {
      mockNative();

      await expectLater(
        lock.hold(() async => throw const SocketException('no route')),
        throwsA(isA<SocketException>()),
      );

      // A leaked lock keeps the Wi-Fi chip awake for the life of the process.
      expect(calls, ['acquire', 'release']);
    });
  });

  group('a lock that cannot be taken never blocks the lookup', () {
    test('native returns false: body still runs, nothing to release', () async {
      mockNative(acquireReturns: false);

      final result = await lock.hold(() async => 'resolved anyway');

      expect(result, 'resolved anyway');
      expect(calls, ['acquire'], reason: 'nothing was acquired, so nothing is released');
    });

    test('a platform error is swallowed and the body still runs', () async {
      mockNative(throws: PlatformException(code: 'WIFI_UNAVAILABLE'));

      expect(await lock.hold(() async => 'resolved anyway'), 'resolved anyway');
      expect(await lock.acquire(), isFalse);
    });

    test('a missing native side is not an error', () async {
      // No handler registered at all — an older APK, or a unit-test engine.
      expect(await lock.acquire(), isFalse);
      expect(await lock.hold(() async => 'resolved anyway'), 'resolved anyway');
      expect(calls, isEmpty);
    });
  });

  group('platforms without the lock', () {
    test('iOS never calls the channel', () async {
      // mDNSResponder resolves .local natively and has no such lock.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      mockNative();

      expect(await lock.hold(() async => 'resolved'), 'resolved');
      expect(calls, isEmpty);
    });
  });
}

/// Stands in for a real socket failure without importing `dart:io` into a
/// test that otherwise needs nothing from it.
class SocketException implements Exception {
  const SocketException(this.message);
  final String message;
}
