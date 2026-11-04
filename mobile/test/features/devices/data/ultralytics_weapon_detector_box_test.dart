import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/data/ultralytics_weapon_detector.dart';

/// The plugin's box contract, pinned.
///
/// `YOLOPlugin.kt` emits each detection as `x1..y2` in bitmap pixels plus
/// `x1_norm..y2_norm` already divided by the bitmap's size, and the response
/// carries `imageSize` alongside. None of that is in the plugin's public Dart
/// API — it is the shape of a loosely typed map — so a plugin upgrade can
/// change it without breaking compilation. These tests are what would notice.
///
/// The stakes are specific: a box read through the wrong convention is not
/// obviously broken. It is a confident, precisely drawn rectangle over the
/// wrong part of the picture. This model has already produced exactly that
/// failure once, scoring mAP 0.0 while being perfectly healthy, because its
/// coordinates were in pixels where the consumer expected 0..1.
void main() {
  group('parseBox', () {
    test('prefers the normalised coordinates', () {
      final box = UltralyticsWeaponDetector.parseBox(const {
        'x1': 128.0,
        'y1': 96.0,
        'x2': 384.0,
        'y2': 288.0,
        'x1_norm': 0.2,
        'y1_norm': 0.2,
        'x2_norm': 0.6,
        'y2_norm': 0.6,
      });

      expect(box, isNotNull);
      expect(box!.left, closeTo(0.2, 1e-9));
      expect(box.top, closeTo(0.2, 1e-9));
      expect(box.right, closeTo(0.6, 1e-9));
      expect(box.bottom, closeTo(0.6, 1e-9));
    });

    test('falls back to pixels only when a frame size is actually stated', () {
      final box = UltralyticsWeaponDetector.parseBox(
        const {'x1': 128.0, 'y1': 96.0, 'x2': 384.0, 'y2': 288.0},
        frameSize: const Size(640, 480),
      );

      expect(box, isNotNull);
      expect(box!.left, closeTo(0.2, 1e-9));
      expect(box.top, closeTo(0.2, 1e-9));
      expect(box.right, closeTo(0.6, 1e-9));
      expect(box.bottom, closeTo(0.6, 1e-9));
    });

    test('refuses to guess when pixels arrive with no frame size', () {
      // The whole point. Dividing by an assumed 640x480 would produce a
      // plausible box from an unknown frame, and nothing downstream could
      // tell it from a correct one.
      expect(
        UltralyticsWeaponDetector.parseBox(
          const {'x1': 128.0, 'y1': 96.0, 'x2': 384.0, 'y2': 288.0},
        ),
        isNull,
      );
    });

    test('returns null when there are no coordinates at all', () {
      expect(
        UltralyticsWeaponDetector.parseBox(
          const {'className': 'knife', 'confidence': 0.9},
        ),
        isNull,
      );
    });

    test('rejects a zero-area box rather than passing it on', () {
      expect(
        UltralyticsWeaponDetector.parseBox(const {
          'x1_norm': 0.4,
          'y1_norm': 0.4,
          'x2_norm': 0.4,
          'y2_norm': 0.9,
        }),
        isNull,
      );
    });

    test('a partial normalised set does not half-read into a wrong box', () {
      // Three of the four keys present is a changed contract, not a usable
      // box. Reading it with a 0.0 default would silently anchor every box to
      // the frame's edge.
      final box = UltralyticsWeaponDetector.parseBox(const {
        'x1_norm': 0.2,
        'y1_norm': 0.2,
        'x2_norm': 0.6,
      });

      expect(box, isNull);
    });
  });

  group('parseFrameSize', () {
    test('reads imageSize', () {
      expect(
        UltralyticsWeaponDetector.parseFrameSize(const {
          'imageSize': {'width': 640, 'height': 480},
        }),
        const Size(640, 480),
      );
    });

    test('returns null when absent or degenerate', () {
      expect(UltralyticsWeaponDetector.parseFrameSize(const {}), isNull);
      expect(
        UltralyticsWeaponDetector.parseFrameSize(const {
          'imageSize': {'width': 0, 'height': 480},
        }),
        isNull,
      );
    });
  });

  group('parseDetections still does what it did', () {
    test('label and confidence survive, and now carry a box', () {
      final detections = UltralyticsWeaponDetector.parseDetections(
        const {
          'boxes': [
            {
              'className': 'knife',
              'confidence': 0.84,
              'x1_norm': 0.1,
              'y1_norm': 0.1,
              'x2_norm': 0.5,
              'y2_norm': 0.7,
            },
          ],
        },
        at: DateTime(2026, 11, 4),
      );

      expect(detections, hasLength(1));
      expect(detections.single.label, 'knife');
      expect(detections.single.confidence, 0.84);
      expect(detections.single.box, isNotNull);
    });

    test('a detection with no box is still a detection', () {
      // It must still reach the scorer. Losing it because it cannot be drawn
      // would make the overlay capable of suppressing an alarm.
      final detections = UltralyticsWeaponDetector.parseDetections(
        const {
          'boxes': [
            {'className': 'pistol', 'confidence': 0.91},
          ],
        },
        at: DateTime(2026, 11, 4),
      );

      expect(detections, hasLength(1));
      expect(detections.single.label, 'pistol');
      expect(detections.single.box, isNull);
    });
  });

  group('resolveLabel', () {
    // The order the model was trained in: data.yaml says `0: pistol,
    // 1: knife`, matching assets/models/weapon_labels.txt.
    const labels = ['pistol', 'knife'];

    test('names the class the plugin could only number', () {
      // Measured on a real device on 2026-11-04: a knife in view reported
      // `class 0`, which read as a firearm. This is that bug.
      expect(UltralyticsWeaponDetector.resolveLabel('class 1', labels), 'knife');
      expect(
        UltralyticsWeaponDetector.resolveLabel('class 0', labels),
        'pistol',
      );
    });

    test('keeps a real label untouched', () {
      // Attaching metadata to the model later must retire this path quietly,
      // not fight it.
      expect(UltralyticsWeaponDetector.resolveLabel('knife', labels), 'knife');
    });

    test('an index past the list is left as it came', () {
      // Better an ugly `class 7` than confidently calling the eighth class a
      // pistol because the list is two long.
      expect(
        UltralyticsWeaponDetector.resolveLabel('class 7', labels),
        'class 7',
      );
      expect(
        UltralyticsWeaponDetector.resolveLabel('class -1', labels),
        'class -1',
      );
    });

    test('no labels loaded still yields a usable detection', () {
      expect(UltralyticsWeaponDetector.resolveLabel('class 1', const []),
          'class 1');
    });

    test('a genuine class name that merely starts with "class" survives', () {
      expect(
        UltralyticsWeaponDetector.resolveLabel('class action', labels),
        'class action',
      );
    });

    test('parseDetections names the detection, not just the resolver', () {
      // The vacuity guard: `resolveLabel` being right is worth nothing if
      // `parseDetections` never calls it.
      final detections = UltralyticsWeaponDetector.parseDetections(
        const {
          'boxes': [
            {'className': 'class 1', 'confidence': 0.61},
          ],
        },
        at: DateTime(2026, 11, 4),
        labels: labels,
      );

      expect(detections.single.label, 'knife');
    });

    test('an unnamed detection still counts toward the alarm', () {
      // `isWeaponClass` is a denylist, so a nameless class must not be
      // silently excluded from scoring just because it could not be named.
      final detections = UltralyticsWeaponDetector.parseDetections(
        const {
          'boxes': [
            {'className': 'class 0', 'confidence': 0.61},
          ],
        },
        at: DateTime(2026, 11, 4),
      );

      expect(detections.single.label, 'class 0');
      expect(detections.single.isWeaponClass, isTrue);
    });
  });
}
