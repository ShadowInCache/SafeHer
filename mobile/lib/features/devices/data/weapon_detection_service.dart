import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/weapon_scorer.dart';

/// Runs the detector over one frame.
///
/// An interface rather than the plugin directly, for the same reason
/// `SafetyForegroundService` is one: the plugin needs a device, and the logic
/// worth testing — how often to infer, what to do when a frame is late, when
/// to forget the window — is all on this side of it.
abstract class WeaponDetector {
  Future<List<WeaponDetection>> detect(Uint8List jpegFrame);
  Future<void> dispose();
}

/// A detector on a platform that has none.
///
/// Returns nothing, which the scorer reads as "a frame was examined and held
/// no weapon". That is the correct reading for web, where the on-device model
/// cannot run and the server path supplies the score instead — but it is only
/// correct because [WeaponDetectionService] is never started on web. Wiring
/// this up as a live detector would report calm from a model that never ran.
class NoopWeaponDetector implements WeaponDetector {
  const NoopWeaponDetector();

  @override
  Future<List<WeaponDetection>> detect(Uint8List jpegFrame) async => const [];

  @override
  Future<void> dispose() async {}
}

/// Consumes the glasses' video and keeps `ThreatSignals.weapon` current.
///
/// ## Why inference is throttled below the frame rate
///
/// The glasses stream 10–15 fps. Running YOLOv8n on every one of those would
/// heat the phone and flatten the battery to no purpose: the scorer votes over
/// a window of frames spread across seconds, so what it needs is *coverage
/// over time*, not every frame. [inferenceInterval] sets the real rate, and
/// frames arriving in between are dropped for detection while still being
/// displayed.
///
/// Frames are also dropped whenever inference is already running. Queueing
/// them instead would build a backlog that grows without bound, and every
/// frame in it is older than the one behind it — on a safety signal, a queue
/// is just a machine for reporting the past.
class WeaponDetectionService {
  WeaponDetectionService({
    required WeaponDetector detector,
    WeaponScorer? scorer,
    this.inferenceInterval = const Duration(milliseconds: 200),
    DateTime Function()? clock,
  })  : _detector = detector,
        _scorer = scorer ?? _defaultScorer(),
        _now = clock ?? DateTime.now;

  /// The window that matches a 5 fps inference rate.
  ///
  /// `WeaponScorer`'s own defaults (5 frames, 3 s) were chosen for the ~2 fps
  /// of a sampled still. At 5 fps those five frames span one second, which is
  /// short enough that a hand moving past the lens looks as persistent as a
  /// weapon held out. Fifteen frames is the same three seconds of evidence the
  /// rule was designed around, and the timeout is widened to match so a brief
  /// stall does not silently empty the window.
  static WeaponScorer _defaultScorer() =>
      WeaponScorer(window: 15, frameTimeout: const Duration(seconds: 5));

  final WeaponDetector _detector;
  final WeaponScorer _scorer;
  final Duration inferenceInterval;
  final DateTime Function() _now;

  final _scores = StreamController<WeaponScore>.broadcast();

  StreamSubscription<Uint8List>? _subscription;
  DateTime? _lastInference;
  bool _busy = false;
  bool _disposed = false;

  Stream<WeaponScore> get scores => _scores.stream;

  /// How many frames arrived while inference was already running.
  ///
  /// Exposed because a number that is always near the frame rate means the
  /// phone cannot keep up with [inferenceInterval], and that is worth knowing
  /// before a user reports the app being hot rather than after.
  int get droppedFrames => _droppedFrames;
  int _droppedFrames = 0;

  /// Begins scoring [frames]. The stream is the glasses' decoded JPEGs.
  void watch(Stream<Uint8List> frames) {
    _subscription?.cancel();
    _droppedFrames = 0;
    _subscription = frames.listen(_onFrame);
  }

  /// The video stopped. Forget the window.
  ///
  /// Frames from before a dropout must not vote alongside frames from after
  /// it: a knife seen once before the glasses disconnected and once a minute
  /// later is two glimpses, not a persistent threat, and combining them
  /// invents evidence that no one observed.
  void onStreamLost() {
    _scorer.reset();
    _lastInference = null;
    if (!_scores.isClosed) _scores.add(_scorer.current(now: _now()));
  }

  Future<void> _onFrame(Uint8List frame) async {
    if (_disposed) return;

    final now = _now();
    final last = _lastInference;
    if (last != null && now.difference(last) < inferenceInterval) return;

    if (_busy) {
      _droppedFrames++;
      return;
    }

    _busy = true;
    _lastInference = now;
    try {
      final detections = await _detector.detect(frame);
      if (_disposed) return;
      final score = _scorer.observe(detections, now: _now());
      if (!_scores.isClosed) _scores.add(score);
    } catch (_) {
      // One failed inference is not evidence about the world, so it records
      // nothing — neither a hit nor an empty frame. Recording an empty frame
      // would let a broken detector quietly vote the score down to zero and
      // look exactly like a camera pointed at nothing.
    } finally {
      _busy = false;
    }
  }

  @visibleForTesting
  WeaponScore currentScore() => _scorer.current(now: _now());

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _detector.dispose();
    await _scores.close();
  }
}
