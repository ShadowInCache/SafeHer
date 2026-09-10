import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/network/api_client.dart';
import 'package:safeher_app/features/safety/data/threat_signal_aggregator.dart';

/// Captures what the app posts to `/alerts/analyze` without touching the
/// network, following `auth_repository_remote_test.dart`.
class _RecordingApiClient implements ApiClient {
  final List<({String path, Map<String, dynamic> body})> posts = [];
  int status = 202;

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
    client.posts.add((
      path: options.path,
      body: jsonDecode(jsonEncode(options.data)) as Map<String, dynamic>,
    ));
    return ResponseBody.fromString(
      '{"ok":true}',
      client.status,
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
  late DateTime now;

  ThreatSignalAggregator build({Duration maxAge = const Duration(seconds: 10)}) =>
      ThreatSignalAggregator(
        apiClient: api,
        maxAge: maxAge,
        clock: () => now,
      );

  setUp(() {
    api = _RecordingApiClient();
    now = DateTime.utc(2026, 9, 2, 12);
  });

  group('what gets sent', () {
    test('a missing modality is absent from the payload, never zero', () {
      // The backend's contract: a zero claims the sensor looked and saw calm,
      // which with no camera attached caps the fused score below the alarm
      // threshold and silently disables automatic dispatch.
      final aggregator = build()..reportGlove(0.8);

      final payload = aggregator.buildPayload()!;
      expect(payload['motion_score'], 0.8);
      expect(payload.containsKey('audio_score'), isFalse);
      expect(payload.containsKey('vision_score'), isFalse);
    });

    test('carries all three under the wire names the backend expects', () {
      final aggregator = build()
        ..reportGlove(0.7)
        ..reportAudio(0.6, label: 'distress')
        ..reportWeapon(0.5, label: 'knife');

      final payload = aggregator.buildPayload()!;
      expect(payload['motion_score'], 0.7);
      expect(payload['audio_score'], 0.6);
      expect(payload['vision_score'], 0.5);
      expect(payload['weapon_label'], 'knife');
    });

    test('nothing fresh means nothing to send', () {
      expect(build().buildPayload(), isNull);
    });

    test('a genuine zero from a live sensor is still reported', () {
      // "The glove is connected and calm" is information, and distinct from
      // "there is no glove". Only staleness may remove a modality.
      final payload = (build()..reportGlove(0.0)).buildPayload()!;
      expect(payload['motion_score'], 0.0);
    });

    test('scores are clamped into range', () {
      final payload = (build()
            ..reportGlove(1.9)
            ..reportAudio(-0.4))
          .buildPayload()!;
      expect(payload['motion_score'], 1.0);
      expect(payload['audio_score'], 0.0);
    });
  });

  group('staleness', () {
    test('a signal older than maxAge is dropped rather than sent', () {
      final aggregator = build(maxAge: const Duration(seconds: 10))
        ..reportWeapon(0.9, label: 'knife');

      now = now.add(const Duration(seconds: 11));
      aggregator.reportGlove(0.4);

      final payload = aggregator.buildPayload()!;
      expect(payload['motion_score'], 0.4);
      expect(
        payload.containsKey('vision_score'),
        isFalse,
        reason: 'glasses that dropped out 11s ago are not reporting calm',
      );
      expect(payload.containsKey('weapon_label'), isFalse);
    });

    test('every signal stale means no post at all', () {
      final aggregator = build(maxAge: const Duration(seconds: 5))
        ..reportGlove(0.9)
        ..reportAudio(0.9);

      now = now.add(const Duration(seconds: 6));
      expect(aggregator.buildPayload(), isNull);
    });
  });

  group('arming', () {
    test('does not post while disarmed', () async {
      final aggregator = build()..reportGlove(0.9);
      await aggregator.flush();
      expect(api.posts, isEmpty);
    });

    test('posts to /alerts/analyze once armed', () async {
      final aggregator = build()
        ..arm()
        ..reportGlove(0.9);

      await aggregator.flush();

      expect(api.posts, hasLength(1));
      expect(api.posts.single.path, contains('/alerts/analyze'));
      expect(api.posts.single.body['motion_score'], 0.9);
      aggregator.dispose();
    });

    test('disarming forgets the readings', () async {
      final aggregator = build()
        ..arm()
        ..reportGlove(0.9)
        ..reportAudio(0.8);

      aggregator.disarm();
      expect(aggregator.buildPayload(), isNull);

      // Re-arming must not resurrect the end of the last journey.
      aggregator.arm();
      expect(aggregator.buildPayload(), isNull);
      aggregator.dispose();
    });
  });

  group('failure', () {
    test('a rejected post does not throw and does not retry', () async {
      api.status = 500;
      final aggregator = build()
        ..arm()
        ..reportGlove(0.9);

      await aggregator.flush();
      await aggregator.flush();

      // Two flushes, two attempts — no queue of readings that were true a
      // moment ago and are not now.
      expect(aggregator.postAttempts, 2);
      aggregator.dispose();
    });
  });
}
