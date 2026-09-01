import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Splits an MJPEG `multipart/x-mixed-replace` body into whole JPEG frames.
///
/// ## Why this is hand-written
///
/// `mjpeg_stream` on pub.dev renders a widget and exposes no bytes. That is
/// enough to *show* the glasses' view and useless for detecting anything in it,
/// because the detector needs the frame, not a picture of it on screen. The
/// format is a boundary marker, a couple of headers and a length, so parsing it
/// costs less than working around a package that will not hand it over.
///
/// ## The part that is easy to get wrong
///
/// Chunks arrive at the size the network felt like, not the size the format is
/// written in. A boundary, a header line or a frame body can be split across
/// any number of them, so nothing may be parsed by looking at one chunk alone.
/// Everything here appends to a buffer and consumes only what is provably
/// complete — and `mjpeg_client_test.dart` feeds it a stream chopped one byte
/// at a time to prove it.
class MjpegParser {
  MjpegParser({this.maxFrameBytes = 2 * 1024 * 1024});

  /// A frame larger than this is treated as a desynchronised stream rather
  /// than a very big photograph. Without a ceiling, one corrupt
  /// `Content-Length` buffers until the phone runs out of memory.
  final int maxFrameBytes;

  final _buffer = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);
  int? _expectedLength;

  static final _headerTerminator = Uint8List.fromList([13, 10, 13, 10]);

  /// Feeds one network chunk in and returns whatever frames it completed.
  List<Uint8List> add(List<int> chunk) {
    _buffer.add(chunk);
    _pending = _buffer.takeBytes();
    final frames = <Uint8List>[];

    while (true) {
      if (_expectedLength == null) {
        final headerEnd = _indexOf(_pending, _headerTerminator);
        if (headerEnd < 0) break;

        final headers = String.fromCharCodes(_pending.sublist(0, headerEnd));
        final length = _contentLength(headers);
        _pending = Uint8List.sublistView(
          _pending,
          headerEnd + _headerTerminator.length,
        );

        if (length == null || length <= 0 || length > maxFrameBytes) {
          // Either no length, or one that cannot be right. Skipping the part
          // is better than trusting it: an unbounded read on a desynchronised
          // stream never recovers, whereas the next boundary is moments away.
          continue;
        }
        _expectedLength = length;
      }

      final needed = _expectedLength!;
      if (_pending.length < needed) break;

      frames.add(Uint8List.fromList(_pending.sublist(0, needed)));
      _pending = Uint8List.sublistView(_pending, needed);
      _expectedLength = null;
    }

    _buffer.add(_pending);
    _pending = Uint8List(0);
    return frames;
  }

  static int? _contentLength(String headers) {
    for (final line in headers.split(RegExp(r'\r?\n'))) {
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      if (line.substring(0, colon).trim().toLowerCase() != 'content-length') {
        continue;
      }
      return int.tryParse(line.substring(colon + 1).trim());
    }
    return null;
  }

  static int _indexOf(Uint8List haystack, Uint8List needle) {
    if (needle.isEmpty || haystack.length < needle.length) return -1;
    final limit = haystack.length - needle.length;
    outer:
    for (var i = 0; i <= limit; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}

/// Whether the glasses' video is actually arriving.
enum GlassesStreamStatus { disconnected, connecting, streaming }

/// Pulls the glasses' MJPEG stream and republishes it as JPEG frames.
///
/// **A dead stream reads as "not watching", never as "watching and seeing
/// nothing".** Those are opposite claims: the second one tells a woman the
/// camera is covering her when nothing is being decoded. So the status stream
/// exists alongside the frames, and it is the platform's answer rather than
/// this class's intention.
class GlassesVideoStream {
  GlassesVideoStream({
    required this.streamUri,
    Dio? dio,
    this.retryDelay = const Duration(seconds: 2),
    this.maxRetryDelay = const Duration(seconds: 30),
  }) : _dio = dio ?? Dio();

  /// Typically `http://<glasses-ip>/stream` on the local network — deliberately
  /// a plain client, not the authenticated API client. These bytes go to the
  /// phone over WiFi and never to the server.
  final Uri streamUri;

  final Duration retryDelay;
  final Duration maxRetryDelay;
  final Dio _dio;

  final _frames = StreamController<Uint8List>.broadcast();
  final _statuses = StreamController<GlassesStreamStatus>.broadcast();

  bool _running = false;
  bool _disposed = false;
  Duration _backoff = Duration.zero;
  GlassesStreamStatus _status = GlassesStreamStatus.disconnected;
  StreamSubscription<Uint8List>? _subscription;

  Stream<Uint8List> get frames => _frames.stream;
  Stream<GlassesStreamStatus> get statuses => _statuses.stream;
  GlassesStreamStatus get status => _status;

  void _publish(GlassesStreamStatus next) {
    if (_status == next || _disposed) return;
    _status = next;
    _statuses.add(next);
  }

  Future<void> start() async {
    if (_running || _disposed) return;
    _running = true;
    _backoff = retryDelay;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    while (_running && !_disposed) {
      _publish(GlassesStreamStatus.connecting);
      try {
        final response = await _dio.getUri<ResponseBody>(
          streamUri,
          options: Options(
            responseType: ResponseType.stream,
            receiveTimeout: const Duration(seconds: 10),
          ),
        );

        final parser = MjpegParser();
        final completer = Completer<void>();
        _publish(GlassesStreamStatus.streaming);
        _backoff = retryDelay;

        _subscription = response.data!.stream.listen(
          (chunk) {
            for (final frame in parser.add(chunk)) {
              if (!_frames.isClosed) _frames.add(frame);
            }
          },
          onError: (Object _) {
            if (!completer.isCompleted) completer.complete();
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );

        await completer.future;
        await _subscription?.cancel();
        _subscription = null;
      } catch (_) {
        // Glasses out of range, asleep, or on another network. Not an error
        // worth surfacing on its own — the status already says disconnected,
        // and this loop is what recovers when they come back.
      }

      if (!_running || _disposed) break;
      _publish(GlassesStreamStatus.disconnected);
      await Future<void>.delayed(_backoff);
      final doubled = _backoff * 2;
      _backoff = doubled > maxRetryDelay ? maxRetryDelay : doubled;
    }
    _publish(GlassesStreamStatus.disconnected);
  }

  Future<void> stop() async {
    _running = false;
    await _subscription?.cancel();
    _subscription = null;
    _publish(GlassesStreamStatus.disconnected);
  }

  @visibleForTesting
  Future<void> dispose() async {
    await stop();
    _disposed = true;
    await _frames.close();
    await _statuses.close();
  }
}
