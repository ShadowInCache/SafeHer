
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

  @override
  Future<List<WeaponDetection>> detect(Uint8List jpegFrame) async {
    if (!await ensureLoaded()) return const [];

    final raw = await _yolo.predict(
      jpegFrame,
      confidenceThreshold: _reportingThreshold,
    );
    return parseDetections(raw, at: DateTime.now());
  }

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
        WeaponDetection(label: label, confidence: confidence, at: at),
      );
    }
    return detections;
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
