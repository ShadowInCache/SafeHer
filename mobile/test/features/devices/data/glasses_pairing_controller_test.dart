import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/local/app_preferences.dart';
import 'package:safeher_app/core/local/local_key_value_store.dart';
import 'package:safeher_app/core/local/onboarding_prefs.dart';
import 'package:safeher_app/features/devices/data/glasses_pairing_controller.dart';

import '../../../test_utils/fake_key_value_store.dart';

/// Answers `GET /status` with whatever the test sets.
class _StubAdapter implements HttpClientAdapter {
  Object? body = const {
    'device': 'safeher-glasses',
    'firmware': '1.0.0',
    'battery': 87,
  };
  int status = 200;
  DioExceptionType? failWith;
  final List<Uri> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    if (failWith != null) {
      throw DioException(requestOptions: options, type: failWith!);
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late ProviderContainer container;
  late FakeKeyValueStore store;
  late _StubAdapter adapter;

  GlassesPairing notifier() => container.read(glassesPairingProvider.notifier);
  GlassesPairingState state() => container.read(glassesPairingProvider);

  setUp(() {
    store = FakeKeyValueStore();
    adapter = _StubAdapter();
    container = ProviderContainer(
      overrides: [
        localKeyValueStoreProvider.overrideWithValue(store),
      ],
    );
    notifier().client = Dio()..httpClientAdapter = adapter;
  });

  tearDown(() => container.dispose());

  group('pairing', () {
    test('saves the address once the camera identifies itself', () async {
      expect(await notifier().pair('safeher-glasses.local'), isTrue);

      expect(state().stage, GlassesPairingStage.reachable);
      expect(state().firmware, '1.0.0');
      expect(state().battery, 87);
      expect(
        container.read(appPreferencesProvider).glassesHost,
        'safeher-glasses.local',
      );
    });

    test('asks the host it was given, at /status', () async {
      await notifier().pair('192.168.1.50');
      expect(adapter.requests.single.toString(), 'http://192.168.1.50/status');
    });

    test('accepts an address that already carries a scheme', () async {
      await notifier().pair('http://192.168.1.50:8080');
      expect(
        adapter.requests.single.toString(),
        'http://192.168.1.50:8080/status',
      );
    });
  });

  group('refusing to pair with the wrong thing', () {
    test('something that answers but is not a camera is rejected', () async {
      // Without this check, pairing would succeed against a router's admin
      // page and the app would claim a camera it does not have.
      adapter.body = const {'device': 'some-router', 'firmware': '2.1'};

      expect(await notifier().pair('192.168.1.1'), isFalse);
      expect(state().stage, GlassesPairingStage.unreachable);
      expect(state().error, contains('not a SafeHer camera'));
      expect(container.read(appPreferencesProvider).glassesHost, isEmpty);
    });

    test('nothing is saved when the camera does not answer', () async {
      adapter.failWith = DioExceptionType.connectionTimeout;

      expect(await notifier().pair('safeher-glasses.local'), isFalse);
      expect(state().error, contains('Check the camera is on'));
      expect(
        container.read(appPreferencesProvider).glassesHost,
        isEmpty,
        reason: 'a saved address that answers nothing would show the app as '
            'paired while no frame ever arrives',
      );
    });

    test('an empty address is rejected without a request', () async {
      expect(await notifier().pair('   '), isFalse);
      expect(adapter.requests, isEmpty);
    });
  });

  group('battery', () {
    test('a zero battery is treated as no reading, not a flat one', () async {
      // Same rule as the glove's heart rate: "no reading" and "flat" must not
      // look alike, and the firmware is told to omit rather than send zero.
      adapter.body = const {
        'device': 'safeher-glasses',
        'firmware': '1.0.0',
        'battery': 0,
      };

      await notifier().pair('safeher-glasses.local');
      expect(state().battery, isNull);
    });

    test('an absent battery is simply absent', () async {
      adapter.body = const {'device': 'safeher-glasses', 'firmware': '1.0.0'};

      await notifier().pair('safeher-glasses.local');
      expect(state().battery, isNull);
      expect(state().stage, GlassesPairingStage.reachable);
    });
  });

  group('unpairing', () {
    test('forgetting the camera clears the stored address', () async {
      await notifier().pair('safeher-glasses.local');
      await notifier().unpair();

      expect(container.read(appPreferencesProvider).glassesHost, isEmpty);
      expect(container.read(glassesPairingProvider).isPaired, isFalse);
    });
  });
}
