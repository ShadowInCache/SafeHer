/// Requires a threatening glove reading to repeat before it can raise an alarm.
///
/// ## Why this exists
///
/// Measured on real hardware, 11 October 2026. With the glove sitting on a
/// desk and nobody touching it, the fusion engine was driven to `critical`
/// six times in four minutes. The log shows why:
///
/// ```
/// 23:47:35  glove 0.96 ... => fused 0.96 [motion] critical
/// 23:47:36  nothing fresh to send
/// 23:47:39  glove 0.92 ... => fused 0.92 [motion] critical
/// 23:47:40  nothing fresh to send      (for the next 30+ seconds)
/// ```
///
/// A reported signal stays fresh in the aggregator for ten seconds, so it can
/// only disappear on the *very next* one-second tick if it was retracted —
/// which happens when the glove classifies `NORMAL`. The true sequence was
/// therefore `NORMAL … NORMAL … one FALL spike … NORMAL … NORMAL`.
///
/// **A real fall cannot look like that.** Someone who falls stays fallen: the
/// glove would report several consecutive windows of elevated motion. A single
/// window of `FALL` bracketed by calm on both sides is a misclassification,
/// and it was reaching the fusion engine unchallenged because the glove is the
/// only reporting modality — so its score became the fused score outright.
///
/// ## Why this is not a new policy
///
/// The same rule already exists three times over in this codebase, and the
/// fusion path was simply the one place it had been left out:
///
/// * the glove firmware debounces `SUDDEN_MOVEMENT` across two windows
///   (`SUDDEN_MOVEMENT_CONFIRMATION_WINDOWS`) — but never gated `FALL`;
/// * `GloveThreatDetector` requires two hits in five seconds before it opens
///   the direct BLE-to-SOS countdown;
/// * `WeaponScorer` will not call a detection persistent below two qualifying
///   frames.
///
/// ## What this deliberately does not delay
///
/// Only the report that feeds **fusion**, and therefore the automatic SOS.
/// The camera still opens on the very first reading, because looking is cheap
/// and reversible and the footage from the pending window is exactly the
/// evidence that matters if the second reading does arrive. The rule is
/// *look immediately, alarm on confirmation* — not *wait before doing
/// anything*.
///
/// The cost is roughly half a second on a genuine fall, since the glove
/// classifies about twice a second. That is the trade the firmware already
/// accepts for `SUDDEN_MOVEMENT`.
class GloveConfirmation {
  GloveConfirmation({
    this.requiredHits = 2,
    this.window = const Duration(seconds: 5),
  }) : assert(requiredHits >= 1);

  /// Consecutive threatening readings needed before one is reported.
  final int requiredHits;

  /// How long a partial streak stays alive without being completed.
  ///
  /// Guards the case where the glove goes silent mid-streak rather than
  /// reporting `NORMAL`: two spikes a minute apart are two spikes, not a
  /// sustained event.
  final Duration window;

  DateTime? _streakStartedAt;
  int _hits = 0;

  /// Hits accumulated so far. Exposed for diagnostics and tests.
  int get hits => _hits;

  /// Records a threatening reading. Returns whether it may now be reported.
  bool confirm(DateTime now) {
    final startedAt = _streakStartedAt;
    if (startedAt == null || now.difference(startedAt) > window) {
      // Either the first hit, or the previous streak went stale.
      _streakStartedAt = now;
      _hits = 1;
    } else {
      _hits++;
    }
    return _hits >= requiredHits;
  }

  /// Breaks the streak.
  ///
  /// Called when the glove reports `NORMAL`, which is its way of saying there
  /// is no threatening motion. Calm between two spikes is precisely what
  /// separates a misclassification from a sustained event, so it must not be
  /// possible for readings either side of it to combine.
  void reset() {
    _streakStartedAt = null;
    _hits = 0;
  }
}
