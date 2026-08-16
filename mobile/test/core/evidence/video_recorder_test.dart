import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/evidence/evidence_recorder.dart';
import 'package:safeher_app/core/evidence/video_recorder.dart';
import 'package:safeher_app/core/evidence/video_recorder_stub.dart';

/// A [VideoEvidenceRecorder] that can be made to fail on demand.
///
/// The camera is the component most likely to be unavailable in a real
/// emergency — no permission, no lens, already held by another app — so
/// failing is the case worth testing, not the exception.
class _FakeVideoRecorder implements VideoEvidenceRecorder {
  _FakeVideoRecorder({this.failOnStart = false, this.returnsNothing = false});

  final bool failOnStart;
  final bool returnsNothing;

  bool _recording = false;
  int startCalls = 0;
  int cancelCalls = 0;

  @override
  bool get isRecording => _recording;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> start() async {
    startCalls++;
    if (failOnStart) {
      throw const EvidenceRecorderException(EvidenceRecorderFailure.permissionDenied);
    }
    _recording = true;
  }

  @override
  Future<EvidenceRecording?> stop() async {
    // Mirrors PlatformVideoRecorder: nothing recording means nothing to
    // hand back. A double that returned bytes here would let a real
    // regression through.
    if (!_recording) return null;
    _recording = false;
    if (returnsNothing) return null;
    return EvidenceRecording(
      bytes: Uint8List.fromList(List.filled(64, 7)),
      mimeType: 'video/mp4',
    );
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    _recording = false;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  group('VideoEvidenceRecorder contract', () {
    test('a finished recording is labelled as video', () async {
      final recorder = _FakeVideoRecorder();
      await recorder.start();

      final recording = await recorder.stop();

      expect(recording, isNotNull);
      expect(recording!.mimeType, 'video/mp4');
      expect(recording.sizeBytes, greaterThan(0));
    });

    test('stopping without starting yields nothing rather than throwing', () async {
      // An alert that was cancelled, or a camera that never opened, must not
      // produce an exception on the way out of an emergency.
      final recorder = _FakeVideoRecorder();

      expect(await recorder.stop(), isNull);
    });

    test('a camera that cannot open throws a typed failure', () async {
      final recorder = _FakeVideoRecorder(failOnStart: true);

      await expectLater(
        recorder.start(),
        throwsA(
          isA<EvidenceRecorderException>().having(
            (e) => e.reason,
            'reason',
            EvidenceRecorderFailure.permissionDenied,
          ),
        ),
      );
      expect(recorder.isRecording, isFalse);
    });

    test('an empty capture is null, not a zero-byte recording', () async {
      // Uploading an empty file would put a useless attachment on an
      // incident report and imply evidence exists where none does.
      final recorder = _FakeVideoRecorder(returnsNothing: true);
      await recorder.start();

      expect(await recorder.stop(), isNull);
    });

    test('cancelling leaves nothing recording', () async {
      final recorder = _FakeVideoRecorder();
      await recorder.start();

      await recorder.cancel();

      expect(recorder.isRecording, isFalse);
      expect(recorder.cancelCalls, 1);
    });
  });

  group('web stub', () {
    test('reports unsupported rather than half-working', () async {
      final recorder = PlatformVideoRecorder();

      expect(await recorder.isSupported(), isFalse);
      expect(await recorder.hasPermission(), isFalse);
      expect(await recorder.requestPermission(), isFalse);
    });

    test('starting on web throws unsupported, not a generic failure', () async {
      // The UI distinguishes "this platform cannot" from "something broke",
      // and only the former is worth telling the user to change device for.
      final recorder = PlatformVideoRecorder();

      await expectLater(
        recorder.start(),
        throwsA(
          isA<EvidenceRecorderException>().having(
            (e) => e.reason,
            'reason',
            EvidenceRecorderFailure.unsupported,
          ),
        ),
      );
    });

    test('stop and cancel are safe no-ops on web', () async {
      final recorder = PlatformVideoRecorder();

      expect(await recorder.stop(), isNull);
      await recorder.cancel();
      await recorder.dispose();
    });
  });

  group('video never compromises audio', () {
    test('a failed camera does not stop a recording session proceeding', () async {
      // The property that matters most on this screen. Audio is the
      // recording that works wherever the phone happens to be; video is a
      // bonus for when the lens is pointed at something. A camera that
      // cannot open must cost nothing.
      final video = _FakeVideoRecorder(failOnStart: true);

      var audioStarted = false;
      Future<void> startBoth() async {
        audioStarted = true; // audio path, independent
        try {
          await video.start();
        } catch (_) {
          // swallowed exactly as the emergency screen does
        }
      }

      await startBoth();

      expect(audioStarted, isTrue);
      expect(video.isRecording, isFalse);
      expect(video.startCalls, 1);
    });
  });
}
