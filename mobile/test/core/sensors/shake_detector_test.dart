import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/sensors/shake_detector.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// A shake hard enough to clear every sensitivity threshold.
AccelerometerEvent _jolt() => AccelerometerEvent(30, 0, 0, DateTime.now());

/// Holding the phone still: gravity only, so net acceleration is ~0.
AccelerometerEvent _still() => AccelerometerEvent(0, 0, 9.80665, DateTime.now());

void main() {
  group('ShakeDetector', () {
    late StreamController<AccelerometerEvent> controller;
    late int fireCount;
    late ShakeDetector detector;

    setUp(() {
      controller = StreamController<AccelerometerEvent>.broadcast();
      fireCount = 0;
    });

    tearDown(() async {
      await detector.stop();
      await controller.close();
    });

    ShakeDetector build({ShakeSensitivity sensitivity = ShakeSensitivity.medium}) {
      return detector = ShakeDetector(
        onShake: () => fireCount++,
        sensitivity: sensitivity,
        accelerometerStream: controller.stream,
      )..start();
    }

    /// Emits [count] jolts spaced far enough apart to count as separate
    /// movements rather than one continuous one.
    Future<void> shake(int count) async {
      for (var i = 0; i < count; i++) {
        controller.add(_jolt());
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      await Future<void>.delayed(Duration.zero);
    }

    test('does not fire while the phone is held still', () async {
      build();
      for (var i = 0; i < 20; i++) {
        controller.add(_still());
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fireCount, 0);
    });

    test('does not fire on a single jolt', () async {
      build();
      await shake(1);
      expect(fireCount, 0);
    });

    test('does not fire on two jolts — three are required', () async {
      build();
      await shake(2);
      expect(fireCount, 0);
    });

    test('fires once after three deliberate shakes', () async {
      build();
      await shake(3);
      expect(fireCount, 1);
    });

    test('treats a burst of consecutive samples as one movement', () async {
      build();
      // No gap between samples: one continuous jolt, not three shakes.
      for (var i = 0; i < 10; i++) {
        controller.add(_jolt());
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fireCount, 0);
    });

    test('does not fire twice for one shaking episode (cooldown)', () async {
      build();
      await shake(3);
      expect(fireCount, 1);
      await shake(3);
      expect(fireCount, 1, reason: 'cooldown should suppress the second alert');
    });

    test('low sensitivity ignores movement that medium would catch', () async {
      build(sensitivity: ShakeSensitivity.low);
      // 15 m/s² total => ~5.2 net, over "high" (9.0)? No — under all of them
      // except nothing; use a value between high and low thresholds.
      for (var i = 0; i < 3; i++) {
        controller.add(AccelerometerEvent(20, 0, 0, DateTime.now()));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      // Net = 20 - 9.81 = 10.19, which clears "high" (9.0) but not "low" (18.0).
      expect(fireCount, 0);
    });

    test('stop() ends listening', () async {
      build();
      await detector.stop();
      expect(detector.isListening, isFalse);
      await shake(5);
      expect(fireCount, 0);
    });

    test('sensitivity levels map to the documented ordering', () {
      expect(ShakeSensitivity.fromLevel(1), ShakeSensitivity.low);
      expect(ShakeSensitivity.fromLevel(2), ShakeSensitivity.medium);
      expect(ShakeSensitivity.fromLevel(3), ShakeSensitivity.high);
      // An out-of-range level must not become the easiest to trigger.
      expect(ShakeSensitivity.fromLevel(99), ShakeSensitivity.medium);
      expect(
        ShakeSensitivity.low.thresholdMetresPerSecondSquared >
            ShakeSensitivity.high.thresholdMetresPerSecondSquared,
        isTrue,
      );
    });
  });
}
