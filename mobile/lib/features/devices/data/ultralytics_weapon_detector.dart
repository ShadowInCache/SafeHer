
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../domain/weapon_scorer.dart';
import 'weapon_detection_service.dart';

/// Runs the trained YOLOv8n detector on the phone, via Ultralytics' plugin.
///
/// ## Why on the phone and not the glasses or the server
///
/// The glasses are an ESP32-S3. YOLOv8n needs roughly two orders of magnitude
/// more compute and memory than that part has, which is recorded in
/// `docs/WEAPON_INFERENCE_PLACEMENT.md` with the arithmetic. And the stream is
/// continuous, so uploading it for server-side inference would mean sending
/// live video of wherever she is, all journey, to be scored — a far larger
/// privacy cost than the alternative and a worse one to explain.
///
/// So the frames arrive over local WiFi and are scored on the device. Nothing
/// leaves the phone but a number.
///
/// ## The conversion that had to match
///
/// The bundled `.tflite` was produced by hand rather than by ultralytics'
/// exporter, which refuses to run on Windows. The first attempt scored mAP
/// **0.0** through ultralytics' own validator while being a perfectly healthy
/// model: its boxes were in absolute pixels, and both the validator and this
/// plugin expect the coordinates normalised to 0..1 and multiply them back up.
///
/// The export now normalises, and re-validating on the 658-image test split
/// gives mAP@0.5 0.9056 against the PyTorch model's 0.907. That measurement is
/// the only reason this class can be trusted — the mismatch produced confident,
/// entirely wrong boxes, and on a phone there is no mAP to notice it with.
class UltralyticsWeaponDetector implements WeaponDetector {
  UltralyticsWeaponDetector({YOLO? yolo})
      : _yolo = yolo ??
            YOLO(
              modelPath: modelAsset,
              task: YOLOTask.detect,
            );

  static const modelAsset = 'assets/models/weapon_yolov8n_fp16.tflite';

  /// Below this the plugin does not even report a box.
  ///
  /// Deliberately lower than [WeaponScorer.confidenceFloor], which is 0.55.
  /// Persistence across frames is a better filter than a high per-frame
  /// threshold, because a high threshold discards the weak-but-real frames
  /// that make a genuine run look persistent — and the model's recall of 0.83
  /// means a real weapon already produces an intermittent signal.
  static const _reportingThreshold = 0.35;

  final YOLO _yolo;
  bool _loaded = false;
  bool _unavailable = false;

  Future<bool> ensureLoaded() async {
    if (_loaded) return true;
    if (_unavailable) return false;
    try {
      _loaded = await _yolo.loadModel();
    } catch (_) {
      _loaded = false;
    }
    // One failure is permanent for this instance. Retrying a model that will
    // not load, once per frame, would spend the battery faster than running it.
    _unavailable = !_loaded;
    return _loaded;
  }

  /// Loads the model ahead of the first frame — see [WeaponDetector.prepare].
  /// Failure is not raised: [ensureLoaded] records it, and `detect` returns
  /// nothing rather than pretending the frame was examined.
  @override
  Future<void> prepare() async => ensureLoaded();

  @override
  Future<List<WeaponDetection>> detect(Uint8List jpegFrame) async {
    if (!await ensureLoaded()) return const [];

    final raw = await _yolo.predict(
      jpegFrame,
      confidenceThreshold: _reportingThreshold,
    );
    final frameSize = parseFrameSize(raw);
    // Remembered rather than recomputed: the overlay needs it to undo the
    // preview's `BoxFit`, and decoding the JPEG again purely to ask its
    // dimensions would double the per-frame cost for a number the plugin
    // already told us.
    if (frameSize != null) _lastFrameSize = frameSize;
    return parseDetections(raw, at: DateTime.now(), frameSize: frameSize);
  }

  @override
  Size? get lastFrameSize => _lastFrameSize;
  Size? _lastFrameSize;

  /// Reads the plugin's result map into the scorer's vocabulary.
  ///
  /// Tolerant on purpose. The plugin documents `YOLOResult` fields but the map
  /// returned by `predict` is loosely typed, and a plugin upgrade that renames
  /// a key must not silently become "no weapons anywhere" — the failure mode
  /// where a safety feature keeps running and always reports calm.
  @visibleForTesting
  static List<WeaponDetection> parseDetections(
    Map<String, dynamic> raw, {
    required DateTime at,
    Size? frameSize,
  }) {
    final boxes = raw['boxes'] ?? raw['detections'] ?? raw['results'];
    if (boxes is! List) return const [];

    final detections = <WeaponDetection>[];
    for (final entry in boxes) {
      if (entry is! Map) continue;

      final label = (entry['className'] ?? entry['class'] ?? entry['label'])
          ?.toString();
      final confidence = _toDouble(entry['confidence'] ?? entry['score']);
      if (label == null || confidence == null) continue;

      detections.add(
        WeaponDetection(
          label: label,
          confidence: confidence,
          at: at,
          box: parseBox(entry, frameSize: frameSize),
        ),
      );
    }
    return detections;
  }

  /// Reads one detection's normalised box, or null when there is not one.
  ///
  /// `YOLOPlugin.kt` emits both `x1..y2` in bitmap pixels and `x1_norm..y2_norm`
  /// already divided by the bitmap's width and height. The normalised pair is
  /// read first because it is the one that survives the frame changing size.
  ///
  /// Falling back to the pixel pair would need the frame dimensions to be
  /// correct, and a box silently divided by the wrong size is exactly the class
  /// of error that once made this model score mAP 0.0 while being perfectly
  /// healthy — confident, precisely drawn, entirely wrong. So the fallback
  /// divides by a frame size only when the response actually states one, and
  /// otherwise returns null: no box at all is a visible failure, a misplaced
  /// box is an invisible one.
  @visibleForTesting
  static WeaponBox? parseBox(Map<dynamic, dynamic> entry, {Size? frameSize}) {
    final left = _toDouble(entry['x1_norm']);
    final top = _toDouble(entry['y1_norm']);
    final right = _toDouble(entry['x2_norm']);
    final bottom = _toDouble(entry['y2_norm']);
    if (left != null && top != null && right != null && bottom != null) {
      final box = WeaponBox(left: left, top: top, right: right, bottom: bottom);
      return box.isUsable ? box : null;
    }

    if (frameSize == null || frameSize.width <= 0 || frameSize.height <= 0) {
      return null;
    }
    final x1 = _toDouble(entry['x1']);
    final y1 = _toDouble(entry['y1']);
    final x2 = _toDouble(entry['x2']);
    final y2 = _toDouble(entry['y2']);
    if (x1 == null || y1 == null || x2 == null || y2 == null) return null;
    final box = WeaponBox(
      left: x1 / frameSize.width,
      top: y1 / frameSize.height,
      right: x2 / frameSize.width,
      bottom: y2 / frameSize.height,
    );
    return box.isUsable ? box : null;
  }

  /// The decoded frame's pixel size, as the plugin reported it.
  ///
  /// Carried so the overlay can work out what `BoxFit.cover` cropped away
  /// without decoding the JPEG a second time just to ask its dimensions.
  @visibleForTesting
  static Size? parseFrameSize(Map<String, dynamic> raw) {
    final size = raw['imageSize'];
    if (size is! Map) return null;
    final width = _toDouble(size['width']);
    final height = _toDouble(size['height']);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return Size(width, height);
  }

  static double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  @override
  Future<void> dispose() async {
    if (!_loaded) return;
    try {
      await _yolo.dispose();
    } catch (_) {
      // Nothing useful to do if the platform side has already gone.
    }
  }
}
