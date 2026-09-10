import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/evidence/evidence_recorder.dart';

/// Records the glasses' microphone as evidence, over WiFi.
///
/// ## Why this exists when the phone already records
///
/// Position. The phone is in a bag, a pocket, or a hand that has been knocked
/// away; the glasses are on her head, pointed at whoever is speaking. For the
/// one recording that may later matter, that difference is worth a second file.
///
/// It is also the only capture path that **does not compete for the phone's
/// microphone**. `MicrophoneArbiter` exists because speech recognition and
/// evidence recording cannot both hold the device — this stream is a network
/// socket, so it runs alongside either without contending for anything.
///
/// ## What this is not
///
/// Not a threat signal. The audio score is computed from the phone's
/// microphone through the platform recogniser, and nothing here feeds the
/// fusion engine. This produces a file for an incident record and nothing
/// more.
///
/// ## Bounded on purpose
///
/// 16 kHz mono 16-bit is about 32 kB per second, so an unbounded recording
/// would reach the server's 25 MB evidence ceiling in roughly thirteen
/// minutes and be rejected after the fact — having spent the whole emergency
/// buffering. [maxDuration] and [maxBytes] stop first, and whatever was
/// captured up to that point is still a usable recording.
class GlassesAudioRecorder {
  GlassesAudioRecorder({
    required this.streamUri,
    Dio? dio,
    this.maxDuration = const Duration(minutes: 2),
    this.maxBytes = 4 * 1024 * 1024,
  }) : _dio = dio ?? Dio();

  /// `http://<glasses-host>/audio`, on the local network.
  ///
  /// Deliberately a plain client rather than the authenticated API client:
  /// these bytes come from a device on the WiFi and must never carry the
  /// user's bearer token.
  final Uri streamUri;

  final Duration maxDuration;
  final int maxBytes;
  final Dio _dio;

  final _buffer = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _subscription;
  Timer? _deadline;
  bool _recording = false;

  bool get isRecording => _recording;

  /// Bytes captured so far. Exposed so a caller can show progress without
  /// stopping the recording.
  int get capturedBytes => _buffer.length;

  /// Begins pulling the stream. Returns false when the glasses do not answer.
  ///
  /// Never throws. This runs during an emergency, alongside a countdown, and a
  /// pair of glasses that is out of range is an ordinary outcome — not a
  /// reason to interrupt anything the user is doing.
  Future<bool> start() async {
    if (_recording) return true;
    _buffer.clear();

    try {
      final response = await _dio.getUri<ResponseBody>(
        streamUri,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      _recording = true;
      _subscription = response.data!.stream.listen(
        (chunk) {
          _buffer.add(chunk);
          if (_buffer.length >= maxBytes) unawaited(_close());
        },
        onError: (Object _) => unawaited(_close()),
        onDone: () => unawaited(_close()),
        cancelOnError: true,
      );

      _deadline = Timer(maxDuration, () => unawaited(_close()));
      return true;
    } catch (_) {
      _recording = false;
      return false;
    }
  }

  /// Stops and returns what was captured, or null if there is nothing usable.
  ///
  /// The firmware sends a 44-byte WAV header before any audio, so a response
  /// carrying only that header is a connection that opened and delivered
  /// silence — returned as null rather than as an empty recording, because an
  /// evidence file containing no audio is worse than no file: it looks on the
  /// incident like something was captured.
  Future<EvidenceRecording?> stop() async {
    await _close();
    final bytes = _buffer.takeBytes();
    if (bytes.length <= _wavHeaderBytes) return null;
    return EvidenceRecording(bytes: bytes, mimeType: 'audio/wav');
  }

  /// Stops and discards. Used when the alert was cancelled, so nothing is kept.
  Future<void> cancel() async {
    await _close();
    _buffer.clear();
  }

  static const _wavHeaderBytes = 44;

  Future<void> _close() async {
    _deadline?.cancel();
    _deadline = null;
    _recording = false;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }
}
