import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import '../domain/weapon_overlay.dart';
import '../domain/weapon_scorer.dart';

/// Runs the detector over one frame.
///
/// An interface rather than the plugin directly, for the same reason
/// `SafetyForegroundService` is one: the plugin needs a device, and the logic
/// worth testing — how often to infer, what to do when a frame is late, when
/// to forget the window — is all on this side of it.
abstract class WeaponDetector {
  /// Loads whatever the detector needs before the first frame arrives.
  ///
  /// Optional, and a no-op by default. It exists because the camera is no
  /// longer open for the whole journey: it is opened when the microphone or
  /// the glove suggests something is happening. A detector that loads its
  /// model on the first `detect()` call would therefore spend its start-up
  /// time in the seconds immediately after a trigger — blind at the one moment
  /// the camera was opened for. Calling this when the journey arms moves that
  /// cost to a time when nothing is waiting on it.
  Future<void> prepare() async {}

  Future<List<WeaponDetection>> detect(Uint8List jpegFrame);
  Future<void> dispose();

  /// The pixel size of the last frame this detector examined, when it knows.
  ///
  /// Null by default, and null forever for any detector that does not report
  /// one. It exists so the overlay can undo the `BoxFit` the preview applies:
  /// a normalised box is a fraction of the *source frame*, and turning that
  /// into a rectangle on screen needs the source's aspect ratio. A detector
  /// that cannot say leaves the overlay unable to draw, which is the correct
  /// outcome — better a missing box than one placed by guesswork.
  Size? get lastFrameSize => null;
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
  Future<void> prepare() async {}

  @override
  Future<List<WeaponDetection>> detect(Uint8List jpegFrame) async => const [];

  @override
  Future<void> dispose() async {}

  @override
  Size? get lastFrameSize => null;
}

/// What the detector actually managed, as counters rather than claims.
///
/// Every field here is a count or a measured duration. There are no targets and
/// no estimates: the rates this feature could be described by — frames per
/// second, inferences per second, latency percentiles — all depend on a
/// specific phone running a specific model against a real stream, and none of
/// them can be obtained on a development machine. So the raw material is
/// recorded and the arithmetic is done from it, on the device, by whoever has
/// one in their hand.
@immutable
class WeaponDetectionMetrics {
  const WeaponDetectionMetrics({
    required this.framesReceived,
    required this.inferencesRun,
    required this.inferencesFailed,
    required this.framesDroppedWhileBusy,
    required this.observedFor,
    required this.latencies,
  });

  /// Frames handed to the service by the video stream.
  final int framesReceived;

  /// Inferences that completed and produced a result.
  final int inferencesRun;

  /// Inferences that threw. Counted separately because a failure records
  /// nothing — neither a detection nor an empty frame — so a rising number
  /// here looks exactly like a calm scene from the outside.
  final int inferencesFailed;

  /// Frames discarded because inference was already running. A figure near
  /// [framesReceived] means the phone cannot keep up with `inferenceInterval`.
  final int framesDroppedWhileBusy;

  final Duration observedFor;

  /// Per-inference durations in microseconds, most recent last, bounded.
  final List<int> latencies;

  double get framesPerSecond => observedFor.inMicroseconds == 0
      ? 0
      : framesReceived / (observedFor.inMicroseconds / 1e6);

  double get inferencesPerSecond => observedFor.inMicroseconds == 0
      ? 0
      : inferencesRun / (observedFor.inMicroseconds / 1e6);

  Duration? get medianLatency => _percentile(0.50);
  Duration? get p95Latency => _percentile(0.95);

  Duration? _percentile(double fraction) {
    if (latencies.isEmpty) return null;
    final sorted = List<int>.from(latencies)..sort();
    // Nearest-rank, which is the honest choice on a few hundred samples:
    // interpolating between two measurements invents a number that was never
    // observed, and at this sample size the difference is noise anyway.
    final rank = (fraction * sorted.length).ceil().clamp(1, sorted.length);
    return Duration(microseconds: sorted[rank - 1]);
  }

  @override
  String toString() => 'WeaponDetectionMetrics('
      'frames $framesReceived, inferences $inferencesRun, '
      'failed $inferencesFailed, dropped $framesDroppedWhileBusy, '
      'fps ${framesPerSecond.toStringAsFixed(1)}, '
      'ips ${inferencesPerSecond.toStringAsFixed(1)}, '
      'median ${medianLatency?.inMilliseconds}ms, '
      'p95 ${p95Latency?.inMilliseconds}ms)';
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
  final _overlayFrames = StreamController<WeaponOverlayFrame>.broadcast();

  StreamSubscription<Uint8List>? _subscription;
  DateTime? _lastInference;
  bool _busy = false;
  bool _disposed = false;

  Stream<WeaponScore> get scores => _scores.stream;

  /// Each inference's detections, for drawing only.
  ///
  /// **A second stream rather than boxes bolted onto [scores], on purpose.**
  /// The two carry different things at different rates and must be allowed to
  /// disagree: a score is a claim about the last fifteen frames and feeds the
  /// alarm, while an overlay frame is what this one frame contained and feeds
  /// a rectangle. Putting them in one object would invite a future reader to
  /// draw from the score or alarm from the box, and both would be wrong.
  ///
  /// Nothing listens to this during fusion. If nobody subscribes, the detector
  /// behaves exactly as it did before this stream existed — a broadcast
  /// controller with no listeners drops what it is given.
  ///
  /// Only successful inferences are published. A failure emits nothing at all,
  /// for the same reason it records nothing: an empty frame would claim the
  /// model looked and saw a weapon-free scene. Boxes left over from before a
  /// failure come down by themselves, because `WeaponOverlayState.staleAfter`
  /// expires anything without a newer result behind it.
  Stream<WeaponOverlayFrame> get overlayFrames => _overlayFrames.stream;

  /// Loads the detector's model before any frame arrives — see
  /// [WeaponDetector.prepare].
  ///
  /// Called when a journey arms, while the camera is still shut. The camera is
  /// now opened by a trigger rather than left running, so a model that loaded
  /// on its first frame would spend its start-up time in the seconds right
  /// after something happened — blind at the moment it was opened for.
  Future<void> prepareDetector() => _detector.prepare();

  /// How many frames arrived while inference was already running.
  ///
  /// Exposed because a number that is always near the frame rate means the
  /// phone cannot keep up with [inferenceInterval], and that is worth knowing
  /// before a user reports the app being hot rather than after.
  int get droppedFrames => _droppedFrames;
  int _droppedFrames = 0;

  int _framesReceived = 0;
  int _inferencesRun = 0;
  int _inferencesFailed = 0;
  DateTime? _watchingSince;
  final List<int> _latenciesMicros = <int>[];

  /// Counters for the rates this feature may not claim without measuring.
  ///
  /// The specification for the overlay asks for frame rate, inference rate and
  /// latency percentiles, and this project does not quote a number it has not
  /// measured. Nothing on this machine can produce those figures — they depend
  /// on a particular phone holding a particular model against a real stream —
  /// so rather than estimate them, the counters that would produce them are
  /// recorded here and read on a device.
  ///
  /// Cheap enough to leave on: four integers and a bounded list of ints, all
  /// updated on the inference path that already costs tens of milliseconds.
  WeaponDetectionMetrics get metrics => WeaponDetectionMetrics(
        framesReceived: _framesReceived,
        inferencesRun: _inferencesRun,
        inferencesFailed: _inferencesFailed,
        framesDroppedWhileBusy: _droppedFrames,
        observedFor: _watchingSince == null
            ? Duration.zero
            : _now().difference(_watchingSince!),
        latencies: List<int>.unmodifiable(_latenciesMicros),
      );

  void _recordLatency(Duration taken) {
    // Bounded so a long journey cannot grow this without limit. The oldest
    // sample is dropped rather than the newest kept out: recent latency is
    // what describes the phone's current state, when it is hot and throttling.
    const cap = 512;
    if (_latenciesMicros.length >= cap) _latenciesMicros.removeAt(0);
    _latenciesMicros.add(taken.inMicroseconds);
  }

  /// Begins scoring [frames]. The stream is the glasses' decoded JPEGs.
  void watch(Stream<Uint8List> frames) {
    _subscription?.cancel();
    _droppedFrames = 0;
    _framesReceived = 0;
    _inferencesRun = 0;
    _inferencesFailed = 0;
    _latenciesMicros.clear();
    _watchingSince = _now();
    // `onError` is not optional here. Without it an error on the frame
    // stream -- the glasses dropping mid-chunk, a malformed JPEG boundary --
    // escapes as an unhandled exception, which is what the device logs showed
    // every time the camera opened. The window is reset rather than ignored:
    // frames from before a fault must not vote alongside frames from after
    // it, for the same reason `onStreamLost` exists.
    _subscription = frames.listen(
      _onFrame,
      onError: (Object error) {
        debugPrint('SafeHer: weapon frame stream error: $error');
        onStreamLost();
      },
      cancelOnError: false,
    );
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

    _framesReceived++;
    final now = _now();
    final last = _lastInference;
    if (last != null && now.difference(last) < inferenceInterval) return;

    if (_busy) {
      _droppedFrames++;
      return;
    }

    _busy = true;
    _lastInference = now;
    final started = Stopwatch()..start();
    try {
      final detections = await _detector.detect(frame);
      _inferencesRun++;
      _recordLatency(started.elapsed);
      // "It ran and found nothing" and "it never ran" look identical on screen
      // and produced identical logs, which cost a whole hardware session to
      // tell apart by hand. One line on the first inference and then one in
      // every hundred settles it, and carries the latency that no measurement
      // off a real device has ever recorded.
      if (_inferencesRun == 1 || _inferencesRun % 100 == 0) {
        debugPrint(
          'SafeHer: weapon inference #$_inferencesRun in '
          '${started.elapsedMilliseconds} ms, '
          '${detections.length} detection(s), '
          'frames received $_framesReceived, dropped $_droppedFrames',
        );
      }
      if (detections.isNotEmpty) {
        // Only while something is actually in view, so this is quiet on an
        // ordinary journey. A class name and a confidence describe the model's
        // output, not the person carrying the phone.
        debugPrint(
          'SafeHer: weapon detections: ${detections.map(
                (d) => '${d.label} ${d.confidence.toStringAsFixed(2)}'
                    '${d.box == null ? ' (no box)' : ''}',
              ).join(', ')}',
        );
      }
      if (_disposed) return;
      final observedAt = _now();
      final score = _scorer.observe(detections, now: observedAt);
      if (!_scores.isClosed) _scores.add(score);
      // Published after the score, so a listener that throws while drawing
      // cannot stop the alarm path from having already been fed.
      if (!_overlayFrames.isClosed) {
        _overlayFrames.add(
          WeaponOverlayFrame(
            detections: detections,
            at: observedAt,
            frameSize: _detector.lastFrameSize,
          ),
        );
      }
    } catch (error, stackTrace) {
      _inferencesFailed++;
      // One failed inference is not evidence about the world, so it records
      // nothing — neither a hit nor an empty frame. Recording an empty frame
      // would let a broken detector quietly vote the score down to zero and
      // look exactly like a camera pointed at nothing.
      //
      // But the reason used to be discarded with it, and that made a detector
      // throwing on every frame indistinguishable from a camera pointed at
      // nothing — the count rose where nobody could see it and the UI said
      // "watching". The first failure is reported in full and then one in
      // every hundred, so a permanent fault is visible without flooding the
      // log at the inference rate.
      if (_inferencesFailed == 1 || _inferencesFailed % 100 == 0) {
        debugPrint(
          'SafeHer: weapon inference failed (#$_inferencesFailed): $error',
        );
        if (_inferencesFailed == 1) {
          debugPrintStack(stackTrace: stackTrace, maxFrames: 8);
        }
      }
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
    await _overlayFrames.close();
  }
}
