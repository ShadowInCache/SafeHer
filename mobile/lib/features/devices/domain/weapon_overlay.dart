/// What the detection overlay draws, and for how long.
///
/// ## Why this is not just "the last detections"
///
/// Inference runs at roughly 5 fps while the glasses stream 10–15, so most
/// displayed frames have no inference of their own. Drawing only on the frames
/// that were scored would make the box blink two frames in three. Holding the
/// last result until the next one arrives is what makes the overlay look
/// continuous, and that hold is the whole reason this type exists.
///
/// The hold is also the danger. A box kept on screen after the weapon left the
/// frame is a lie in the direction that matters least — but a box kept after
/// the *detector stopped running* is a lie in the direction that matters most,
/// because it shows a working detector when there is none. So the hold is
/// bounded by [staleAfter] and the overlay goes dark rather than keeping the
/// last thing it saw.
///
/// ## This type cannot raise an alarm
///
/// Nothing here feeds `ThreatSignals.weapon`. The score is computed by
/// `WeaponScorer` from the same detections on a different rule — a vote over a
/// window of frames — and the two deliberately disagree: a single frame with a
/// knife at 0.9 draws a box immediately and moves the score hardly at all. The
/// box is what the model saw; the score is what the system believes. Drawing is
/// allowed to be eager because drawing is not an accusation.
library;

import 'dart:ui' show Size;

import 'weapon_scorer.dart';

/// One inference's worth of drawable detections.
class WeaponOverlayFrame {
  const WeaponOverlayFrame({
    required this.detections,
    required this.at,
    this.frameSize,
  });

  /// Only detections that carry a usable box and clear the draw threshold.
  final List<WeaponDetection> detections;

  /// When the inference that produced these completed.
  final DateTime at;

  /// The source frame's pixel size, needed to undo the preview's `BoxFit`.
  /// Null when the detector did not report one, in which case nothing is
  /// drawn — see [WeaponDetector.lastFrameSize].
  final Size? frameSize;

  bool get isEmpty => detections.isEmpty;

  /// An inference that examined a frame and found nothing worth drawing.
  ///
  /// Distinct from "no inference has happened", which is a null frame. The
  /// difference decides whether the overlay clears the previous boxes or keeps
  /// holding them: a frame that looked and saw nothing is evidence the weapon
  /// has gone, and the boxes come down.
  factory WeaponOverlayFrame.empty({required DateTime at, Size? frameSize}) =>
      WeaponOverlayFrame(detections: const [], at: at, frameSize: frameSize);

  @override
  String toString() =>
      'WeaponOverlayFrame(${detections.length} boxes at $at)';
}

/// Decides what is on screen right now.
///
/// Holds no clock and no stream: [visibleAt] is asked, which is what lets the
/// hold-and-expire rule be tested without waiting in real time.
class WeaponOverlayState {
  const WeaponOverlayState({
    this.latest,
    this.drawThreshold = defaultDrawThreshold,
    this.staleAfter = defaultStaleAfter,
  });

  /// Below this a detection is not drawn.
  ///
  /// Deliberately the detector's own reporting threshold (0.35) and **not**
  /// `WeaponScorer.confidenceFloor` (0.55). The two answer different questions.
  /// The scorer's floor decides what may contribute to an alarm, where a false
  /// positive costs someone a police call. The overlay's threshold decides what
  /// a user is shown, where a weak box is informative — it is visibly weak,
  /// labelled with its confidence, and she can see for herself that the model
  /// is unsure. Hiding everything under 0.55 would make the model look more
  /// certain than it is.
  static const defaultDrawThreshold = 0.35;

  /// How long a result may stay on screen without a newer one behind it.
  ///
  /// One second is about five inference intervals at the deployed 200 ms. Long
  /// enough that an ordinary stall does not make the box flicker; short enough
  /// that a detector which has stopped — a stream drop, a model failure, a
  /// phone too busy to infer — clears the screen while the video is still
  /// playing, rather than leaving a stale rectangle over live video.
  static const defaultStaleAfter = Duration(seconds: 1);

  final WeaponOverlayFrame? latest;
  final double drawThreshold;
  final Duration staleAfter;

  /// The detections that should be painted at [now].
  ///
  /// Empty when nothing has been inferred yet, when the last inference found
  /// nothing, or when the last inference is older than [staleAfter].
  List<WeaponDetection> visibleAt(DateTime now) {
    final frame = latest;
    if (frame == null) return const [];
    if (now.difference(frame.at) > staleAfter) return const [];
    return frame.detections;
  }

  /// Whether the last result has aged out. Separate from [visibleAt] being
  /// empty, because "the detector went quiet" and "the detector saw nothing"
  /// look identical on screen and must not look identical in a log.
  bool isStaleAt(DateTime now) {
    final frame = latest;
    if (frame == null) return false;
    return now.difference(frame.at) > staleAfter;
  }

  Size? get frameSize => latest?.frameSize;

  /// Records one inference, keeping only what is drawable.
  ///
  /// Filters on the box being usable as well as on confidence: the server path
  /// returns detections with no box at all, and those are real detections that
  /// simply cannot be drawn. They still reach the scorer; they just do not
  /// reach the screen.
  WeaponOverlayState withFrame(
    List<WeaponDetection> detections, {
    required DateTime at,
    Size? frameSize,
  }) {
    final drawable = <WeaponDetection>[];
    for (final detection in detections) {
      if (!detection.isWeaponClass) continue;
      if (detection.confidence < drawThreshold) continue;
      final box = detection.box;
      if (box == null || !box.isUsable) continue;
      drawable.add(detection);
    }
    return copyWith(
      latest: WeaponOverlayFrame(
        detections: drawable,
        at: at,
        frameSize: frameSize ?? this.frameSize,
      ),
    );
  }

  /// The video stopped, or the detector did. Take the boxes down now rather
  /// than letting them age out: there is no prospect of a newer result, and a
  /// box over a frozen or absent stream is the worst thing this overlay can
  /// show.
  WeaponOverlayState cleared() => WeaponOverlayState(
        drawThreshold: drawThreshold,
        staleAfter: staleAfter,
      );

  WeaponOverlayState copyWith({WeaponOverlayFrame? latest}) =>
      WeaponOverlayState(
        latest: latest ?? this.latest,
        drawThreshold: drawThreshold,
        staleAfter: staleAfter,
      );
}
