import 'dart:collection';

/// Requires a threatening glove reading to be *dense*, not merely repeated,
/// before it can raise an alarm.
///
/// ## What the hardware actually emits
///
/// The glove notifies about twice a second and alternates. A real event looks
/// like `FALL -> NORMAL -> FALL -> NORMAL`, not a run of consecutive FALLs.
/// Measured on a Samsung SM M166P, 17 October:
///
/// ```
/// 14:59:56  FALL 0.89     14:59:58  FALL 0.99     14:59:59  FALL 0.98
/// 15:00:01  FALL 0.84     15:00:03  FALL 0.99
/// ```
///
/// — with silent `NORMAL` readings between every pair.
///
/// An earlier version of this class required two *consecutive* non-NORMAL
/// readings and reset on every `NORMAL`. Against that alternation it could
/// never accumulate: twenty-plus readings, several at 0.99, every one logged
/// `awaiting confirmation (1/2)` and **nothing reached fusion at all**. That
/// is a worse failure than the false alarms it replaced — the glove could not
/// raise an alarm under any circumstances.
///
/// ## Why density, and why these numbers
///
/// Consecutiveness does not separate a real event from a spurious one, because
/// both alternate. Rate does. Taking the two captures of the same firmware:
///
/// | capture                          | readings          | max in any 5 s |
/// |----------------------------------|-------------------|----------------|
/// | 11 Oct, glove idle on a desk     | 3 spikes over 8 s | 2              |
/// | 17 Oct, glove deliberately moved | ~20 over 60 s     | 3 or more      |
///
/// So [requiredHits] is 3 within a [window] of 5 seconds: the highest density
/// the idle glove reached was 2, and a real event clears 3 readily. Both
/// numbers come from recorded hardware, not from judgement, and the tests
/// replay both captures tick by tick.
///
/// `NORMAL` no longer resets the streak — it is simply a reading that is not
/// a hit, and ages out of the window like any other.
///
/// ## What this deliberately does not delay
///
/// Only the report that feeds fusion, and therefore the automatic SOS. The
/// camera still opens on the very first reading, because looking is cheap and
/// reversible and footage from the pending window is the evidence that matters
/// if the event is real. Look immediately; alarm on confirmation.
class GloveConfirmation {
  GloveConfirmation({
    this.requiredHits = 3,
    this.window = const Duration(seconds: 5),
  }) : assert(requiredHits >= 1);

  /// Threatening readings needed inside [window] before one is reported.
  final int requiredHits;

  /// How far back a reading still counts toward the current density.
  final Duration window;

  final Queue<DateTime> _hits = Queue<DateTime>();

  /// Readings still inside the window. Exposed for diagnostics and tests.
  int get hits => _hits.length;

  /// Records a threatening reading. Returns whether it may now be reported.
  bool confirm(DateTime now) {
    _hits.addLast(now);
    _evict(now);
    return _hits.length >= requiredHits;
  }

  /// Ages the window forward without recording a hit.
  ///
  /// Called when the glove reports `NORMAL`. Unlike the previous version this
  /// does **not** clear the streak: the glove alternates, so treating calm as
  /// a reset made confirmation unreachable. Calm simply contributes nothing
  /// and lets older hits expire.
  void observeCalm(DateTime now) => _evict(now);

  /// Forgets everything. Used when a journey ends, so the next one cannot
  /// inherit a partial streak.
  void reset() => _hits.clear();

  void _evict(DateTime now) {
    while (_hits.isNotEmpty && now.difference(_hits.first) > window) {
      _hits.removeFirst();
    }
  }
}
