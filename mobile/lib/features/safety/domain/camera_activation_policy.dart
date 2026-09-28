import 'package:flutter/foundation.dart';

/// What opened the camera, for the incident record and the UI.
enum CameraTrigger {
  /// A phrase the classifier scored as threatening or distressed.
  audio,

  /// The glove reported a fall, or force applied by someone else.
  glove,

  /// Still open because the detector is currently seeing something.
  weapon,
}

/// Decides when the glasses' camera should be streaming.
///
/// ## Why the camera is not simply on for the whole journey
///
/// It used to be. Continuous video costs the glasses' battery, the phone's
/// battery and the link, and it means the camera watches everywhere she goes
/// for the length of a journey in order to catch the seconds that matter. The
/// microphone and the glove are cheap and already running, so they can say when
/// those seconds have arrived, and the camera can stay shut until then.
///
/// So this is a policy object, kept apart from the pipeline that acts on it:
/// deciding *when to look* is a product judgement with thresholds and timers in
/// it, and it is worth being able to test that judgement without a camera, a
/// phone or a journey.
///
/// ## What the numbers are for
///
/// [dwell] must comfortably exceed the detector's evidence window — the scorer
/// votes over 15 frames at about 5 fps, roughly three seconds — or the camera
/// would close before a score could mean anything. [maxOpen] bounds the damage
/// of a false trigger that keeps re-extending. [cooldown] stops a chattering
/// signal from cycling the camera, which would cost more battery than leaving
/// it open and produce worse evidence than either.
///
/// **[urgentGloveScore] deliberately bypasses the cooldown.** A fall is the one
/// signal that describes something having already gone wrong, and making it
/// wait out a timer to save battery is the wrong trade.
class CameraActivationPolicy {
  CameraActivationPolicy({
    this.dwell = const Duration(seconds: 30),
    this.cooldown = const Duration(seconds: 10),
    this.maxOpen = const Duration(minutes: 3),
    this.audioScore = 0.5,
    this.gloveScore = 0.7,
    this.urgentGloveScore = 0.95,
  });

  /// How long the camera stays open after the most recent trigger.
  final Duration dwell;

  /// How long after closing before an ordinary trigger may reopen it.
  final Duration cooldown;

  /// A ceiling on one continuous opening, however often it is extended.
  final Duration maxOpen;

  /// Matches `AudioThreatReading.isElevated`, so the camera opens on exactly
  /// the utterances the app already treats as elevated.
  final double audioScore;

  /// On `ThreatPipeline.gloveScore`'s scale: `SUDDEN_MOVEMENT` at full
  /// confidence, or `FALL` at 0.7 and above.
  final double gloveScore;

  /// A confident `FALL`. Opens the camera even inside the cooldown.
  final double urgentGloveScore;

  DateTime? _openedAt;
  DateTime? _closesAt;
  DateTime? _closedAt;
  CameraTrigger? _openedBy;

  bool get isOpen => _closesAt != null;

  /// What opened the camera, or null while it is shut.
  CameraTrigger? get openedBy => _openedBy;

  /// When the camera is currently due to close. Null while shut.
  DateTime? get closesAt => _closesAt;

  /// Reports a scored utterance. Returns true if the camera should now be open.
  bool reportAudio(double score, {required DateTime now}) {
    if (score < audioScore) return isOpen;
    return _open(CameraTrigger.audio, now: now, urgent: false);
  }

  /// Reports a glove classification's score. Returns true if the camera should
  /// now be open.
  bool reportGlove(double score, {required DateTime now}) {
    if (score < gloveScore) return isOpen;
    return _open(
      CameraTrigger.glove,
      now: now,
      urgent: score >= urgentGloveScore,
    );
  }

  /// Keeps the camera open while the detector is still seeing something.
  ///
  /// Only extends an opening that already exists — a weapon score cannot open
  /// the camera, because a closed camera produces no frames and therefore no
  /// score. Anything else would be a claim about a picture nobody took.
  void reportWeapon(double score, {required DateTime now}) {
    if (!isOpen || score <= 0) return;
    _closesAt = now.add(dwell);
    _openedBy = CameraTrigger.weapon;
  }

  /// Whether the camera's time is up — the dwell has elapsed, or the opening
  /// has run past [maxOpen].
  bool shouldClose({required DateTime now}) {
    final closesAt = _closesAt;
    final openedAt = _openedAt;
    if (closesAt == null || openedAt == null) return false;
    if (now.difference(openedAt) >= maxOpen) return true;
    return !now.isBefore(closesAt);
  }

  /// Records that the camera has been closed, starting the cooldown.
  void close({required DateTime now}) {
    if (!isOpen) return;
    _closesAt = null;
    _openedAt = null;
    _openedBy = null;
    _closedAt = now;
  }

  /// Forgets everything, including the cooldown. For disarming: the next
  /// journey must not begin inside the last one's timers.
  void reset() {
    _closesAt = null;
    _openedAt = null;
    _openedBy = null;
    _closedAt = null;
  }

  bool _open(CameraTrigger trigger, {required DateTime now, required bool urgent}) {
    if (isOpen) {
      // Already watching: push the closing time out rather than restarting,
      // so a run of triggers keeps one continuous recording instead of
      // chopping it into pieces the scorer must not combine.
      _closesAt = now.add(dwell);
      _openedBy ??= trigger;
      return true;
    }

    if (!urgent && _inCooldown(now)) return false;

    _openedAt = now;
    _closesAt = now.add(dwell);
    _openedBy = trigger;
    return true;
  }

  bool _inCooldown(DateTime now) {
    final closedAt = _closedAt;
    return closedAt != null && now.difference(closedAt) < cooldown;
  }

  @override
  String toString() => isOpen
      ? 'CameraActivationPolicy(open, by $_openedBy, until $_closesAt)'
      : 'CameraActivationPolicy(closed)';
}

/// Convenience for logging, kept out of the class so the policy stays pure.
@visibleForTesting
String describeTrigger(CameraTrigger trigger) => switch (trigger) {
      CameraTrigger.audio => 'a phrase the classifier scored as elevated',
      CameraTrigger.glove => 'the glove',
      CameraTrigger.weapon => 'something still in view',
    };
