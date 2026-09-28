import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/data/weapon_detection_service.dart';
import 'package:safeher_app/features/devices/domain/weapon_scorer.dart';

/// A detector that answers whatever the test tells it to, and counts how often
/// it was asked. The counting is the point of most of these tests: the service
/// exists to run the model *less* often than frames arrive.
class _FakeDetector implements WeaponDetector {
  List<WeaponDetection> result = const [];
  Duration delay = Duration.zero;
  Object? throwOnDetect;
  int calls = 0;
  bool disposed = false;

  /// Counted so the pipeline can be held to pre-loading the model when a
  /// journey arms, rather than paying that cost in the seconds after a trigger
  /// — when the camera has just been opened because something is happening.
  int prepareCalls = 0;

  @override
  Future<void> prepare() async => prepareCalls++;

  @override
  Future<List<WeaponDetection>> detect(Uint8List jpegFrame) async {
    calls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (throwOnDetect != null) throw throwOnDetect!;
    return result;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  late _FakeDetector detector;
  late StreamController<Uint8List> frames;
  late DateTime now;

  final frame = Uint8List.fromList([0xFF, 0xD8, 0x00, 0xFF, 0xD9]);

  WeaponDetection seen(String label, double confidence) =>
      WeaponDetection(label: label, confidence: confidence, at: now);

  WeaponDetectionService build({
    Duration interval = const Duration(milliseconds: 200),
    WeaponScorer? scorer,
  }) =>
      WeaponDetectionService(
        detector: detector,
        scorer: scorer,
        inferenceInterval: interval,
        clock: () => now,
      );

  setUp(() {
    detector = _FakeDetector();
    frames = StreamController<Uint8List>();
    now = DateTime.utc(2026, 9, 2, 12);
  });

  tearDown(() {
    // Deliberately not returned. `close()` on a single-subscription controller
    // that was never listened to returns a future that never completes, and
    // returning it here would hang whichever test did not call `watch` — which
    // is exactly what happened, as a 30-second timeout blamed on the last test
    // in the file rather than on this line.
    frames.close();
  });

  /// Lets the frame's async handler finish before the test asserts.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('throttling', () {
    test('runs the model once per interval, not once per frame', () async {
      final service = build(interval: const Duration(milliseconds: 200))
        ..watch(frames.stream);

      // Fifteen frames arriving across one second, as the glasses send them.
      for (var i = 0; i < 15; i++) {
        now = now.add(const Duration(milliseconds: 66));
        frames.add(frame);
        await settle();
      }

      // ~1s at 200ms spacing is five inferences, not fifteen.
      expect(detector.calls, lessThanOrEqualTo(6));
      expect(detector.calls, greaterThanOrEqualTo(4));
      await service.dispose();
    });

    test('the first frame is examined immediately', () async {
      final service = build()..watch(frames.stream);
      frames.add(frame);
      await settle();

      expect(detector.calls, 1);
      await service.dispose();
    });

    test('drops frames arriving while inference is still running', () async {
      detector.delay = const Duration(milliseconds: 50);
      final service = build(interval: Duration.zero)..watch(frames.stream);

      frames.add(frame);
      await settle();
      // Second frame arrives mid-inference.
      frames.add(frame);
      await settle();

      expect(service.droppedFrames, greaterThan(0));
      await service.dispose();
    });
  });

  group('scoring', () {
    test('publishes a score for each examined frame', () async {
      detector.result = [seen('knife', 0.9)];
      final service = build(interval: Duration.zero)..watch(frames.stream);

      final scores = <WeaponScore>[];
      service.scores.listen(scores.add);

      frames.add(frame);
      await settle();

      expect(scores, hasLength(1));
      expect(scores.single.strongestLabel, 'knife');
      await service.dispose();
    });

    test('one strong frame does not produce a strong score', () async {
      // The whole point of the window: a single confident frame is a
      // reflection until proven otherwise.
      detector.result = [seen('knife', 0.95)];
      final service = build(interval: Duration.zero)..watch(frames.stream);

      frames.add(frame);
      await settle();

      expect(service.currentScore().value, lessThan(0.2));
      await service.dispose();
    });

    test('a persistent weapon builds a strong score', () async {
      detector.result = [seen('knife', 0.9)];
      final service = build(
        interval: Duration.zero,
        scorer: WeaponScorer(window: 5, frameTimeout: const Duration(seconds: 5)),
      )..watch(frames.stream);

      for (var i = 0; i < 5; i++) {
        now = now.add(const Duration(milliseconds: 200));
        detector.result = [seen('knife', 0.9)];
        frames.add(frame);
        await settle();
      }

      expect(service.currentScore().value, greaterThan(0.8));
      await service.dispose();
    });
  });

  group('when things go wrong', () {
    test('a failed inference records nothing at all', () async {
      // Not an empty frame: recording one would let a broken detector vote the
      // score down to zero, looking exactly like a camera seeing nothing.
      detector.result = [seen('knife', 0.9)];
      final service = build(
        interval: Duration.zero,
        scorer: WeaponScorer(window: 5, frameTimeout: const Duration(seconds: 5)),
      )..watch(frames.stream);

      for (var i = 0; i < 3; i++) {
        now = now.add(const Duration(milliseconds: 200));
        frames.add(frame);
        await settle();
      }
      final beforeFailure = service.currentScore();

      detector.throwOnDetect = StateError('interpreter died');
      now = now.add(const Duration(milliseconds: 200));
      frames.add(frame);
      await settle();

      expect(service.currentScore().qualifyingFrames,
          beforeFailure.qualifyingFrames);
      await service.dispose();
    });

    test('losing the stream clears the window', () async {
      // A knife seen once before a dropout and once a minute later is two
      // glimpses, not persistence.
      detector.result = [seen('knife', 0.9)];
      final service = build(interval: Duration.zero)..watch(frames.stream);

      frames.add(frame);
      await settle();
      expect(service.currentScore().qualifyingFrames, 1);

      service.onStreamLost();
      expect(service.currentScore().qualifyingFrames, 0);
      expect(service.currentScore().value, 0);
      await service.dispose();
    });

    test('disposing releases the detector', () async {
      final service = build();
      await service.dispose();
      expect(detector.disposed, isTrue);
    });
  });
}
