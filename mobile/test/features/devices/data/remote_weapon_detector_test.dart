import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/network/api_client.dart';
import 'package:safeher_app/features/devices/data/remote_weapon_detector.dart';

/// Captures uploads to `/alerts/weapon-frame` without touching the network.
class _RecordingApiClient implements ApiClient {
  final List<String> posts = [];
  Map<String, dynamic> body = const {
    'available': true,
    'weapon_confidence': 0.82,
    'weapon_label': 'knife',
  };

  @override
  late final Dio dio = Dio()
    ..httpClientAdapter = _StubAdapter(this)
    ..options.baseUrl = 'http://localhost/api/v1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.client);

  final _RecordingApiClient client;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    client.posts.add(options.path);
    return ResponseBody.fromString(
      jsonEncode(client.body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _RecordingApiClient api;
  final frame = Uint8List.fromList([0xFF, 0xD8, 0x00, 0xFF, 0xD9]);

  setUp(() => api = _RecordingApiClient());

  RemoteWeaponDetector build({
    Duration interval = Duration.zero,
  }) =>
      RemoteWeaponDetector(apiClient: api, minimumInterval: interval);

  group('uploading', () {
    test('posts the frame and returns the detection', () async {
      final detections = await build().detect(frame);

      expect(api.posts.single, contains('/alerts/weapon-frame'));
      expect(detections, hasLength(1));
      expect(detections.single.label, 'knife');
      expect(detections.single.confidence, closeTo(0.82, 1e-9));
    });

    test('a frame the server found nothing in returns no detections', () async {
      api.body = const {
        'available': true,
        'weapon_confidence': 0.0,
        'weapon_label': null,
      };

      expect(await build().detect(frame), isEmpty);
    });
  });

  group('refusing to invent calm', () {
    test('an unavailable server model throws rather than reporting nothing',
        () async {
      // The distinction the fusion design rests on. Returning an empty list
      // would record a frame that was examined and held no weapon, which is a
      // claim nobody made -- and a zero score caps the fused total below the
      // alarm threshold.
      api.body = const {'available': false, 'reason': 'untrained'};

      final detector = build();
      await expectLater(
        detector.detect(frame),
        throwsA(isA<WeaponDetectorUnavailable>()),
      );
      expect(detector.unavailable, isTrue);
    });

    test('it stops asking once told there is no model', () async {
      api.body = const {'available': false, 'reason': 'untrained'};
      final detector = build();

      await detector.detect(frame).catchError((Object _) => <Never>[]);
      await detector.detect(frame).catchError((Object _) => <Never>[]);

      // A deployment without the model will not grow one mid-journey, and
      // re-asking spends the user's data to be told the same thing.
      expect(api.posts, hasLength(1));
    });
  });

  group('throttling', () {
    test('a frame arriving too soon is not uploaded', () async {
      final detector = build(interval: const Duration(seconds: 5));

      await detector.detect(frame);
      await expectLater(
        detector.detect(frame),
        throwsA(isA<WeaponDetectorThrottled>()),
      );

      expect(api.posts, hasLength(1),
          reason: 'every upload is a round trip and a server inference');
    });
  });
}
