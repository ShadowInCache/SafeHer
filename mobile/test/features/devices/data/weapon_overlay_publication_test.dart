import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/data/weapon_detection_service.dart';
import 'package:safeher_app/features/devices/domain/weapon_overlay.dart';
import 'package:safeher_app/features/devices/domain/weapon_scorer.dart';

/// What the detection service publishes for drawing, and what it must not let
/// that publication change.
///
/// The overlay is a display feature bolted onto a path that dispatches
/// emergency alerts. The tests that matter here are not the ones showing boxes
/// appear; they are the ones showing the alarm behaves identically whether
/// anybody is drawing or not.
class _FakeDetector implements WeaponDetector {
  List<WeaponDetection> result = const [];
  Object? throwOnDetect;
  int calls = 0;

  @override
  Size? lastFrameSize = const Size(640, 480);

  @override
  Future<void> prepare() async {}

  @override
  Future<List<WeaponDetection>> detect(Uint8List jpegFrame) async {
    calls++;
    if (throwOnDetect != null) throw throwOnDetect!;
    return result;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late _FakeDetector detector;
  late StreamController<Uint8List> frames;
  late DateTime now;

  final frame = Uint8List.fromList([0xFF, 0xD8, 0x00, 0xFF, 0xD9]);

  WeaponDetection knife({double confidence = 0.80, WeaponBox? box}) =>
      WeaponDetection(
        label: 'knife',
        confidence: confidence,
        at: now,
        box: box ??
            const WeaponBox(left: 0.2, top: 0.2, right: 0.6, bottom: 0.7),
      );

  WeaponDetectionService build() => WeaponDetectionService(
        detector: detector,
        inferenceInterval: Duration.zero,
        clock: () => now,
      );

  setUp(() {
    detector = _FakeDetector();
    frames = StreamController<Uint8List>();
    now = DateTime(2026, 11, 4, 12);
  });

  // Deliberately not awaited. `close()` on a single-subscription controller
  // with no listener returns a future that never completes, and a test that
  // never called `watch` -- or whose service already cancelled -- would hang
  // on it. `weapon_detection_service_test.dart` records the same trap.
  tearDown(() {
    frames.close();
  });

  /// Lets the frame's async handler finish before the test asserts.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('publication', () {
    test('a successful inference publishes its detections and frame size',
        () async {
      final service = build();
      detector.result = [knife()];
      final published = <WeaponOverlayFrame>[];
      service.overlayFrames.listen(published.add);

      service.watch(frames.stream);
      frames.add(frame);
      await settle();

      expect(published, hasLength(1));
      expect(published.single.detections.single.label, 'knife');
      expect(published.single.frameSize, const Size(640, 480));
      expect(published.single.at, now);
      await service.dispose();
    });

    test('a failed inference publishes nothing at all', () async {
      // Not an empty frame. An empty frame means the model looked and the
      // scene held no weapon; a failure means nothing was established. The
      // overlay clears by going stale instead, which keeps "I saw nothing"
      // and "I could not look" from rendering as the same claim.
      final service = build();
      detector.throwOnDetect = StateError('inference blew up');
      final published = <WeaponOverlayFrame>[];
      service.overlayFrames.listen(published.add);

      service.watch(frames.stream);
      frames.add(frame);
      await settle();

      expect(published, isEmpty);
      await service.dispose();
    });

    test('a frame examined with nothing in it publishes an empty frame',
        () async {
      final service = build();
      detector.result = const [];
      final published = <WeaponOverlayFrame>[];
      service.overlayFrames.listen(published.add);

      service.watch(frames.stream);
      frames.add(frame);
      await settle();

      expect(published, hasLength(1));
      expect(published.single.isEmpty, isTrue);
      await service.dispose();
    });

    test('a detector that reports no frame size publishes none', () async {
      final service = build();
      detector.lastFrameSize = null;
      detector.result = [knife()];
      final published = <WeaponOverlayFrame>[];
      service.overlayFrames.listen(published.add);

      service.watch(frames.stream);
      frames.add(frame);
      await settle();

      expect(published.single.frameSize, isNull);
      await service.dispose();
    });
  });

  group('the alarm path is unaffected', () {
    test('scores are identical whether or not anything is drawing', () async {
      Future<List<double>> run({required bool withOverlayListener}) async {
        final localFrames = StreamController<Uint8List>();
        final localDetector = _FakeDetector()..result = [knife()];
        final service = WeaponDetectionService(
          detector: localDetector,
          inferenceInterval: Duration.zero,
          clock: () => now,
        );
        final scores = <double>[];
        service.scores.listen((s) => scores.add(s.value));
        if (withOverlayListener) {
          service.overlayFrames.listen((_) {});
        }
        service.watch(localFrames.stream);
        for (var i = 0; i < 4; i++) {
          localFrames.add(frame);
          await settle();
        }
        await service.dispose();
        localFrames.close();
        return scores;
      }

      expect(
        await run(withOverlayListener: true),
        equals(await run(withOverlayListener: false)),
      );
    });

    test('the score is published before the boxes are', () async {
      // Ordering is the protection against a painter that throws: by the time
      // anything can fail while drawing, the fusion engine has already been
      // told. Asserted as an order rather than by throwing from a listener,
      // because an exception escaping a stream handler fails the test for a
      // reason unrelated to what is being checked.
      final service = build();
      detector.result = [knife()];
      final order = <String>[];
      service.scores.listen((_) => order.add('score'));
      service.overlayFrames.listen((_) => order.add('overlay'));

      service.watch(frames.stream);
      frames.add(frame);
      await settle();

      expect(order, equals(<String>['score', 'overlay']));
      await service.dispose();
    });

    test('a detection carrying a box scores exactly as one without', () async {
      // Position is a display concern. If a box could change the score, the
      // overlay would have become part of the alarm, which is the thing this
      // feature is required not to do.
      Future<double> scoreFor(WeaponDetection detection) async {
        final localFrames = StreamController<Uint8List>();
        final service = WeaponDetectionService(
          detector: _FakeDetector()..result = [detection],
          inferenceInterval: Duration.zero,
          clock: () => now,
        );
        var last = 0.0;
        service.scores.listen((s) => last = s.value);
        service.watch(localFrames.stream);
        for (var i = 0; i < 3; i++) {
          localFrames.add(frame);
          await settle();
        }
        await service.dispose();
        localFrames.close();
        return last;
      }

      final withBox = await scoreFor(knife());
      final withoutBox = await scoreFor(
        WeaponDetection(label: 'knife', confidence: 0.80, at: now),
      );

      expect(withBox, equals(withoutBox));
    });

    test('publishing does not make the detector run more often', () async {
      final service = build();
      detector.result = [knife()];
      service.overlayFrames.listen((_) {});

      service.watch(frames.stream);
      frames.add(frame);
      await settle();
      frames.add(frame);
      await settle();

      expect(detector.calls, 2, reason: 'one inference per released frame');
      await service.dispose();
    });
  });

  group('shutdown', () {
    test('disposing closes the overlay stream', () async {
      final service = build();
      var closed = false;
      service.overlayFrames.listen((_) {}, onDone: () => closed = true);

      await service.dispose();
      await settle();

      expect(closed, isTrue);
    });

    test('nothing is published after disposal', () async {
      final service = build();
      detector.result = [knife()];
      final published = <WeaponOverlayFrame>[];
      service.overlayFrames.listen(published.add);

      service.watch(frames.stream);
      await service.dispose();
      frames.add(frame);
      await settle();

      expect(published, isEmpty);
    });
  });

  group('metrics', () {
    // These counters exist so the rates this feature is described by can be
    // measured on a device instead of estimated here. The tests check the
    // bookkeeping, which is all that can be checked without a phone.
    test('counts frames, inferences and the frames dropped while busy',
        () async {
      final service = WeaponDetectionService(
        detector: detector,
        // Non-zero, so the second frame of each pair is throttled out rather
        // than inferred: that is the deployed behaviour being counted.
        inferenceInterval: const Duration(milliseconds: 200),
        clock: () => now,
      );
      detector.result = [knife()];
      service.watch(frames.stream);

      for (var i = 0; i < 6; i++) {
        now = now.add(const Duration(milliseconds: 100));
        frames.add(frame);
        await settle();
      }

      final metrics = service.metrics;
      expect(metrics.framesReceived, 6);
      expect(metrics.inferencesRun, 3, reason: 'one per 200 ms interval');
      expect(metrics.inferencesFailed, 0);
      await service.dispose();
    });

    test('counts a failed inference separately from a calm one', () async {
      // The distinction matters: a failure records nothing at all, so from the
      // outside a detector that is throwing looks exactly like one watching a
      // quiet street.
      final service = build();
      detector.throwOnDetect = StateError('no');
      service.watch(frames.stream);
      frames.add(frame);
      await settle();

      expect(service.metrics.inferencesFailed, 1);
      expect(service.metrics.inferencesRun, 0);
      await service.dispose();
    });

    test('percentiles come back null until something has been measured', () {
      final service = build();
      expect(service.metrics.medianLatency, isNull);
      expect(service.metrics.p95Latency, isNull);
    });

    test('percentiles are nearest-rank over the samples', () {
      const metrics = WeaponDetectionMetrics(
        framesReceived: 10,
        inferencesRun: 10,
        inferencesFailed: 0,
        framesDroppedWhileBusy: 0,
        observedFor: Duration(seconds: 2),
        latencies: [
          10000, 20000, 30000, 40000, 50000,
          60000, 70000, 80000, 90000, 100000,
        ],
      );

      expect(metrics.medianLatency, const Duration(milliseconds: 50));
      expect(metrics.p95Latency, const Duration(milliseconds: 100));
      expect(metrics.framesPerSecond, closeTo(5, 1e-9));
      expect(metrics.inferencesPerSecond, closeTo(5, 1e-9));
    });

    test('rates are zero rather than NaN before any time has passed', () {
      const metrics = WeaponDetectionMetrics(
        framesReceived: 0,
        inferencesRun: 0,
        inferencesFailed: 0,
        framesDroppedWhileBusy: 0,
        observedFor: Duration.zero,
        latencies: [],
      );

      expect(metrics.framesPerSecond, 0);
      expect(metrics.inferencesPerSecond, 0);
    });

    test('watching a new stream starts the counters again', () async {
      final service = build();
      detector.result = [knife()];
      service.watch(frames.stream);
      frames.add(frame);
      await settle();
      expect(service.metrics.framesReceived, 1);

      final second = StreamController<Uint8List>();
      service.watch(second.stream);

      expect(service.metrics.framesReceived, 0,
          reason: 'counters describe the current stream, not all time');
      await service.dispose();
      second.close();
    });
  });
}
