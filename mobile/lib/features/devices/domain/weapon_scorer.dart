/// Turns a stream of weapon detections into the fusion engine's
/// `weapon_score`, and refuses to be fooled by one frame.
///
/// **Why this is a separate object.** Running the model and deciding what its
/// output means are different jobs. The model says "there is a knife at 0.84 in
/// this frame". Whether that is evidence of danger depends on whether it was
/// also there in the frames either side, and that is a question about time, not
/// about images. Keeping it here means the rule can be argued with in a test
/// rather than by waving a knife at a phone.
///
/// ## The rule
///
/// A detection counts only if its confidence clears [confidenceFloor]. The
/// score is then driven by how many of the last [window] frames carried a
/// qualifying detection — not by the single best frame.
///
/// ```
///   0.84, 0.88, 0.86  ->  persistent, strong signal
///   0.42, 0.08, 0.03  ->  a reflection, and scored as one
/// ```
///
/// This matters more here than it looks. `weapon` carries the largest weight in
/// the fusion engine precisely because a knife is unambiguous — but that
/// assumption only holds for a *real* detection. A single high-confidence frame
/// on a phone screen, a poster, or a chef's knife on a worktop would otherwise
/// inherit that weight and push the fused score most of the way to an alarm.
///
/// The trained detector's own numbers argue for this too: recall 0.827 means
/// roughly one weapon in six is missed per frame, so a genuine weapon in view
/// produces an intermittent signal rather than a solid one. A rule demanding an
/// unbroken run would miss real weapons; a rule accepting one frame would fire
/// on noise. A vote over a window is the shape that fits both.
library;

import 'dart:collection';

/// One thing the detector claims to have seen in one frame.
class WeaponDetection {
  const WeaponDetection({
    required this.label,
    required this.confidence,
    required this.at,
  });

  /// `pistol` or `knife`, as `assets/models/weapon_labels.txt` orders them.
  final String label;

  /// 0.0–1.0 from the model.
  final double confidence;

  final DateTime at;

  @override
  String toString() => 'WeaponDetection($label, ${confidence.toStringAsFixed(2)})';
}

/// The score, and enough of the reasoning to explain it on an incident.
class WeaponScore {
  const WeaponScore({
    required this.value,
    required this.qualifyingFrames,
    required this.framesConsidered,
    this.strongestLabel,
    this.strongestConfidence,
  });

  /// 0.0–1.0, ready for `ThreatSignals.weapon`.
  final double value;

  final int qualifyingFrames;
  final int framesConsidered;

  /// What the most confident qualifying frame saw. Carried for the incident
  /// record and the summary — it is not what produced [value].
  final String? strongestLabel;
  final double? strongestConfidence;

  bool get isPersistent => qualifyingFrames >= 2;

  @override
  String toString() =>
      'WeaponScore(${value.toStringAsFixed(2)}, '
      '$qualifyingFrames/$framesConsidered frames'
      '${strongestLabel == null ? '' : ', strongest $strongestLabel'})';
}

/// Scores weapon detections over a sliding window of frames.
///
/// Deliberately holds no clock, no provider and no model. [now] is injected so
/// a test does not have to sleep, and the detector is somebody else's problem.
class WeaponScorer {
  WeaponScorer({
    this.confidenceFloor = 0.55,
    this.window = 5,
    this.frameTimeout = const Duration(seconds: 3),
  }) : assert(window > 0);

  /// Below this, a detection is not counted at all.
  ///
  /// Lower than the model's own default operating point on purpose. Precision
  /// (0.901) runs above recall (0.827), so the detector is already tuned
  /// conservative; the persistence rule below is a better place to reject noise
  /// than a high per-frame threshold, because a high threshold discards the
  /// weak-but-real frames that make a run look persistent.
  final double confidenceFloor;

  /// How many recent frames vote.
  final int window;

  /// A frame older than this is dropped even if the window is not full.
  /// Without it, a detection from before the camera cut out could combine with
  /// one after it into a "persistent" run that never happened — the same
  /// mistake the glove's detector guards against across a BLE dropout.
  final Duration frameTimeout;

  final Queue<_Frame> _frames = Queue<_Frame>();

  /// Records one frame's worth of detections and returns the current score.
  ///
  /// Pass an empty list for a frame the model looked at and found nothing.
  /// That does not reduce the score directly — persistence is measured against
  /// [window], not against however many frames happened to arrive — but it
  /// occupies a slot, so it stops the score rising and eventually pushes older
  /// hits out of the window. Simply not calling this is a different thing
  /// again: it means no frame arrived at all, and a long enough gap expires
  /// the window through [frameTimeout].
  WeaponScore observe(List<WeaponDetection> detections, {required DateTime now}) {
    _expire(now);

    final qualifying = detections
        .where((d) => d.confidence >= confidenceFloor)
        .toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    _frames.addLast(_Frame(now, qualifying.isEmpty ? null : qualifying.first));
    while (_frames.length > window) {
      _frames.removeFirst();
    }

    return _score();
  }

  /// The score without recording a new frame — for a UI that polls.
  WeaponScore current({required DateTime now}) {
    _expire(now);
    return _score();
  }

  /// Forgets everything. Call when the camera disconnects, so frames from
  /// before the gap cannot vote alongside frames from after it.
  void reset() => _frames.clear();

  void _expire(DateTime now) {
    _frames.removeWhere((f) => now.difference(f.at) > frameTimeout);
  }

  WeaponScore _score() {
    if (_frames.isEmpty) {
      return const WeaponScore(value: 0, qualifyingFrames: 0, framesConsidered: 0);
    }

    final hits = _frames.where((f) => f.best != null).toList();
    if (hits.isEmpty) {
      return WeaponScore(
        value: 0,
        qualifyingFrames: 0,
        framesConsidered: _frames.length,
      );
    }

    hits.sort((a, b) => b.best!.confidence.compareTo(a.best!.confidence));
    final strongest = hits.first.best!;

    // Persistence scales the confidence rather than replacing it. A single
    // 0.95 frame out of five scores 0.19 — visible, nowhere near an alarm. Five
    // frames at 0.95 score 0.95. Both halves have to be true for the signal to
    // be strong, which is the point.
    final persistence = hits.length / window;
    final meanConfidence =
        hits.map((f) => f.best!.confidence).reduce((a, b) => a + b) / hits.length;

    return WeaponScore(
      value: (meanConfidence * persistence).clamp(0.0, 1.0),
      qualifyingFrames: hits.length,
      framesConsidered: _frames.length,
      strongestLabel: strongest.label,
      strongestConfidence: strongest.confidence,
    );
  }
}

class _Frame {
  const _Frame(this.at, this.best);
  final DateTime at;
  final WeaponDetection? best;
}
