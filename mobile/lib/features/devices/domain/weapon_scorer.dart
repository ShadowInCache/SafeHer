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
/// The trained detector's own numbers argue for this too: measured recall of
/// 0.805 at this floor means roughly one weapon in five is missed per frame, so
/// a genuine weapon in view produces an intermittent signal rather than a solid
/// one. A rule demanding an unbroken run would miss real weapons; a rule
/// accepting one frame would fire on noise. A vote over a window is the shape
/// that fits both.
///
/// ## Where this rule does not protect us
///
/// The window vote only dilutes an error that happens *once*. It was measured
/// against errors that repeat, and they are the common kind.
///
/// On 3,218 weapon-free hand-held objects — a phone, a purse, a banknote, a
/// card — 14.6% produced a detection at [confidenceFloor]. Expanding each still
/// into five frames the way a camera differs frame to frame, the result is
/// bimodal: 69.6% never fire and **11.8% fire on all five**, with little in
/// between. A model that mistakes an object does not flicker; it is steadily
/// wrong, and five agreeing frames score the full confidence.
///
/// So 13.8% of weapon-free objects produce a score over 0.55 here, and 4.2%
/// sustain one at or above 0.75 — which, because `fuse` renormalises over the
/// signals that reported, *is* the fused score when the camera is the only
/// thing talking. A purse measured 0.908. That clears the 0.75 auto-SOS
/// threshold in five one-second posts against a 45-second camera dwell.
///
/// Nothing in this class can fix that, and raising [confidenceFloor] only
/// trades it against recall: at 0.75 the false-positive rate falls to 5.7% but
/// recall falls to 0.66. The cause is upstream — every one of the 7,539 images
/// the detector trained on contains a weapon, so it was never shown what "no
/// weapon" looks like. The fix is background images in the training set, and
/// the negatives are already on disk.
///
/// See `tests/test_weapon_model_metrics.py`, which pins all of the above.
library;

import 'dart:collection';

/// Where in the frame a detection sat, in normalised 0..1 coordinates.
///
/// **Normalised rather than pixels, deliberately.** The overlay has to land on
/// a widget whose size is decided by the layout and whose aspect ratio rarely
/// matches the camera's, so a pixel box would have to be re-scaled by whoever
/// drew it and would be wrong the moment the frame size changed. Fractions of
/// the source frame survive every resize, and the one transform that remains —
/// the `BoxFit` the preview uses — is applied once, where the painting happens.
///
/// The fields are the plugin's `x1_norm`/`y1_norm`/`x2_norm`/`y2_norm`, which
/// `YOLOPlugin.kt` computes by dividing the box by the decoded bitmap's own
/// width and height. They are not clamped here: a model may legitimately put an
/// edge slightly outside the frame, and clamping is the painter's business
/// because only the painter knows what is visible after cropping.
class WeaponBox {
  const WeaponBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  /// A box with no area tells the overlay nothing and would paint as a line.
  bool get isUsable =>
      width > 0 && height > 0 && left.isFinite && top.isFinite &&
      right.isFinite && bottom.isFinite;

  @override
  String toString() => 'WeaponBox(${left.toStringAsFixed(3)}, '
      '${top.toStringAsFixed(3)}, ${right.toStringAsFixed(3)}, '
      '${bottom.toStringAsFixed(3)})';
}

/// One thing the detector claims to have seen in one frame.
class WeaponDetection {
  const WeaponDetection({
    required this.label,
    required this.confidence,
    required this.at,
    this.box,
  });

  /// `pistol` or `knife` for the shipped detector.
  ///
  /// Whatever the detector reports, not a value this app controls. On device
  /// the name comes from metadata inside the `.tflite`; `weapon_labels.txt` is
  /// read only by the backend detector and has no effect here. If a model
  /// without that metadata is bundled, the plugin reports `"class 0"` instead
  /// and `isWeaponClass` has nothing to match on.
  final String label;

  /// 0.0–1.0 from the model.
  final double confidence;

  final DateTime at;

  /// Where it sat in the frame, when the detector reported a position.
  ///
  /// **Nullable, and scoring must never read it.** The server path
  /// (`/alerts/weapon-frame`) returns only a label and a confidence, so a web
  /// detection genuinely has no box, and a detector that invented one would be
  /// drawing a rectangle nobody measured. `WeaponScorer` ignores this field
  /// entirely: a detection with a box and a detection without one are worth
  /// exactly the same to the alarm, because position is a display concern and
  /// persistence is the safety concern.
  final WeaponBox? box;

  /// Classes a detector may report that are explicitly *not* weapons.
  ///
  /// Empty in effect for the shipped 2-class model, which can only ever say
  /// `pistol` or `knife`. It exists for the 6-class detector, which names the
  /// objects it used to mistake for weapons — and naming them is the entire
  /// point of that model. Measured on the 1,385 held-out negatives: it emits
  /// 10,960 boxes whose best class is one of these four. Counted as weapons,
  /// they would make the false-positive rate catastrophically worse than the
  /// 2-class model it replaces; rejected, the frame-level rate is 2.5% on the
  /// INT8 ONNX and 2.6% on the fp16 TFLite that a phone would actually load.
  ///
  /// The filter matches on the class *name*, so it only works if the bundled
  /// model carries class-name metadata — without it the plugin reports
  /// `"class 2"`, nothing here matches, and all 10,960 boxes count as weapons.
  /// That was the live state until 2026-11-02. See
  /// `tests/test_weapon_model_metadata.py`, which fails if a future export
  /// drops the metadata again.
  ///
  /// The Spanish names are the source dataset's, kept rather than translated so
  /// they match `data.yaml` and the exported label file exactly.
  static const nonWeaponLabels = <String>{
    'smartphone',
    'monedero', // wallet
    'billete', // banknote
    'tarjeta', // card
  };

  /// Whether this detection is of a class that can raise the alarm.
  ///
  /// Deliberately a *reject* list and not an allow list. An allow list of
  /// {pistol, knife} would mean that a plugin upgrade renaming its classes, or
  /// a label file read as indices, silently produces "no weapons anywhere" —
  /// the failure mode where a safety feature keeps running and always reports
  /// calm. `UltralyticsWeaponDetector.parseDetections` is tolerant for the same
  /// reason and says so. An unrecognised label therefore still counts; only the
  /// four classes known to be harmless are dropped.
  bool get isWeaponClass =>
      !nonWeaponLabels.contains(label.trim().toLowerCase());

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
  /// Lower than the model's own default operating point on purpose. Measured on
  /// the 658-image held-out test split at this floor, precision (0.932) runs
  /// above recall (0.805), so the detector is already tuned conservative; the
  /// persistence rule below is a better place to reject noise than a high
  /// per-frame threshold, because a high threshold discards the weak-but-real
  /// frames that make a run look persistent.
  ///
  /// That precision is measured only on images that contain a weapon, which is
  /// the limit of what the dataset can say. See the class doc above for what
  /// this floor does on weapon-free frames.
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

    // Class first, then confidence. Both detectors build `WeaponDetection`
    // from their own wire format, so this is the one place every path funnels
    // through — filtering in either detector would leave the other open.
    final qualifying = detections
        .where((d) => d.isWeaponClass && d.confidence >= confidenceFloor)
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
