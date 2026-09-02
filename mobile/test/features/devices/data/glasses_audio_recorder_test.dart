import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/data/glasses_audio_recorder.dart';

/// Serves a controllable WAV stream, the way the glasses firmware does.
class _StubAdapter implements HttpClientAdapter {
  final controller = StreamController<Uint8List>();
  bool failConnect = false;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    if (failConnect) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody(controller.stream, 200, headers: {
      Headers.contentTypeHeader: ['audio/wav'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _StubAdapter adapter;
  late Dio dio;

  /// The 44-byte header the firmware sends before any audio.
  Uint8List header() => Uint8List(44)
    ..setAll(0, 'RIFF'.codeUnits)
    ..setAll(8, 'WAVE'.codeUnits);

  Uint8List pcm(int bytes) => Uint8List(bytes)..fillRange(0, bytes, 7);

  GlassesAudioRecorder build({
    Duration maxDuration = const Duration(minutes: 2),
    int maxBytes = 4 * 1024 * 1024,
  }) =>
      GlassesAudioRecorder(
        streamUri: Uri.parse('http://safeher-glasses.local/audio'),
        dio: dio,
        maxDuration: maxDuration,
        maxBytes: maxBytes,
      );

  setUp(() {
    adapter = _StubAdapter();
    dio = Dio()..httpClientAdapter = adapter;
  });

  tearDown(() {
    if (!adapter.controller.isClosed) adapter.controller.close();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('capturing', () {
    test('collects the stream into a WAV recording', () async {
      final recorder = build();
      expect(await recorder.start(), isTrue);

      adapter.controller.add(header());
      adapter.controller.add(pcm(3200));
      await settle();

      final recording = await recorder.stop();
      expect(recording, isNotNull);
      expect(recording!.mimeType, 'audio/wav');
      expect(recording.bytes.length, 44 + 3200);
    });

    test('reports progress without stopping', () async {
      final recorder = build();
      await recorder.start();

      adapter.controller.add(header());
      adapter.controller.add(pcm(1600));
      await settle();

      expect(recorder.capturedBytes, 44 + 1600);
      expect(recorder.isRecording, isTrue);
      await recorder.cancel();
    });
  });

  group('refusing to produce a misleading file', () {
    test('a header with no audio is no recording at all', () async {
      // An evidence file containing no audio is worse than no file: on the
      // incident it looks like something was captured.
      final recorder = build();
      await recorder.start();

      adapter.controller.add(header());
      await settle();

      expect(await recorder.stop(), isNull);
    });

    test('glasses that do not answer fail quietly', () async {
      adapter.failConnect = true;
      final recorder = build();

      expect(await recorder.start(), isFalse);
      expect(recorder.isRecording, isFalse);
      expect(await recorder.stop(), isNull);
    });

    test('cancelling discards what was captured', () async {
      final recorder = build();
      await recorder.start();

      adapter.controller.add(header());
      adapter.controller.add(pcm(3200));
      await settle();

      await recorder.cancel();
      expect(recorder.capturedBytes, 0);
      expect(await recorder.stop(), isNull);
    });
  });

  group('bounds', () {
    test('stops itself at the byte ceiling', () async {
      // Unbounded, this would reach the server's 25 MB evidence limit and be
      // rejected after spending the whole emergency buffering.
      final recorder = build(maxBytes: 2000);
      await recorder.start();

      adapter.controller.add(header());
      adapter.controller.add(pcm(4000));
      await settle();

      expect(recorder.isRecording, isFalse);
      final recording = await recorder.stop();
      expect(recording, isNotNull);
      expect(recording!.bytes.length, greaterThan(44));
    });

    test('stops itself at the time limit', () async {
      final recorder = build(maxDuration: const Duration(milliseconds: 40));
      await recorder.start();

      adapter.controller.add(header());
      adapter.controller.add(pcm(800));
      await Future<void>.delayed(const Duration(milliseconds: 90));

      expect(recorder.isRecording, isFalse);
      // What was captured before the deadline is still usable.
      expect((await recorder.stop())!.bytes.length, 44 + 800);
    });

    test('starting twice does not open a second connection', () async {
      final recorder = build();
      await recorder.start();
      await recorder.start();

      expect(adapter.requests, 1);
      await recorder.cancel();
    });
  });
}
