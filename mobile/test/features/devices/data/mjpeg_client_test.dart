import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/data/mjpeg_client.dart';

/// The parser's whole job is to not care how the network split the bytes. So
/// every case here is run twice: once with the body delivered whole, and once
/// one byte at a time. If the second ever diverges from the first, the parser
/// is reading something it has not fully received.
void main() {
  /// Builds an ESP32-camera style multipart body.
  Uint8List body(List<List<int>> frames, {String boundary = 'frame'}) {
    final out = <int>[];
    for (final frame in frames) {
      out.addAll('--$boundary\r\n'.codeUnits);
      out.addAll('Content-Type: image/jpeg\r\n'.codeUnits);
      out.addAll('Content-Length: ${frame.length}\r\n\r\n'.codeUnits);
      out.addAll(frame);
      out.addAll('\r\n'.codeUnits);
    }
    return Uint8List.fromList(out);
  }

  /// A JPEG-shaped payload: SOI, filler, EOI.
  List<int> jpeg(int size, {int fill = 0x41}) =>
      [0xFF, 0xD8, ...List.filled(size - 4, fill), 0xFF, 0xD9];

  List<Uint8List> parseWhole(Uint8List bytes) =>
      MjpegParser().add(bytes);

  List<Uint8List> parseByteByByte(Uint8List bytes) {
    final parser = MjpegParser();
    final frames = <Uint8List>[];
    for (final byte in bytes) {
      frames.addAll(parser.add([byte]));
    }
    return frames;
  }

  group('frame extraction', () {
    test('reads a single frame', () {
      final payload = jpeg(64);
      for (final parse in [parseWhole, parseByteByByte]) {
        final frames = parse(body([payload]));
        expect(frames, hasLength(1));
        expect(frames.single, equals(payload));
      }
    });

    test('reads several frames of differing sizes', () {
      final payloads = [jpeg(32), jpeg(200, fill: 0x42), jpeg(8, fill: 0x43)];
      for (final parse in [parseWhole, parseByteByByte]) {
        final frames = parse(body(payloads));
        expect(frames, hasLength(3));
        for (var i = 0; i < payloads.length; i++) {
          expect(frames[i], equals(payloads[i]), reason: 'frame $i');
        }
      }
    });

    test('a boundary split across chunks still yields one whole frame', () {
      // The exact failure this parser exists to avoid: a header terminator
      // straddling two TCP reads. Cutting at every offset covers all of them.
      final payload = jpeg(48);
      final bytes = body([payload]);

      for (var cut = 1; cut < bytes.length; cut++) {
        final parser = MjpegParser();
        final frames = <Uint8List>[
          ...parser.add(bytes.sublist(0, cut)),
          ...parser.add(bytes.sublist(cut)),
        ];
        expect(frames, hasLength(1), reason: 'split at byte $cut');
        expect(frames.single, equals(payload), reason: 'split at byte $cut');
      }
    });

    test('emits nothing until a frame is complete', () {
      final payload = jpeg(100);
      final bytes = body([payload]);
      final parser = MjpegParser();

      // Everything but the final byte of the payload.
      expect(parser.add(bytes.sublist(0, bytes.length - 3)), isEmpty);
      expect(parser.add(bytes.sublist(bytes.length - 3)), hasLength(1));
    });
  });

  group('refusing to trust the stream', () {
    test('skips a part whose Content-Length is impossible', () {
      // A corrupt length must not become an unbounded read. The part is
      // skipped and the parser resynchronises on the next real frame.
      final good = jpeg(40);
      final corrupt = Uint8List.fromList([
        ...'--frame\r\nContent-Type: image/jpeg\r\nContent-Length: 99999999\r\n\r\n'
            .codeUnits,
        ...body([good]),
      ]);

      final frames = MjpegParser(maxFrameBytes: 1024).add(corrupt);
      expect(frames, hasLength(1));
      expect(frames.single, equals(good));
    });

    test('skips a part with no Content-Length at all', () {
      final good = jpeg(24);
      final missing = Uint8List.fromList([
        ...'--frame\r\nContent-Type: image/jpeg\r\n\r\n'.codeUnits,
        ...body([good]),
      ]);

      expect(MjpegParser().add(missing), hasLength(1));
    });

    test('header matching is case insensitive', () {
      final payload = jpeg(16);
      final bytes = Uint8List.fromList([
        ...'--frame\r\ncontent-type: image/jpeg\r\nCONTENT-LENGTH: ${payload.length}\r\n\r\n'
            .codeUnits,
        ...payload,
      ]);
      expect(MjpegParser().add(bytes).single, equals(payload));
    });

    test('an empty chunk changes nothing', () {
      final parser = MjpegParser();
      expect(parser.add(const []), isEmpty);
      expect(parser.add(body([jpeg(20)])), hasLength(1));
    });
  });
}
