import '../../../shared/models/threat_level.dart';
import 'glove_protocol.dart';

/// Decides when the glove's classifications justify raising an alarm.
///
/// Kept as a plain class with no Riverpod, no navigation and no clock of its
/// own: this is the piece that decides whether to summon people to someone's
/// location, and it should be possible to argue with it in a test rather than
/// by wearing a glove.
///
/// ## Why a single classification is not enough
///
/// The model emits a class per inference window. One `FALL` can be a glove
/// dropped on a table, a glove being taken off, or a sleeve caught on a door.
/// Dispatching on one reading would make the feature fire during ordinary
/// life, and a feature that cries wolf gets switched off -- at which point it
/// protects nobody, which is a worse outcome than it never having existed.
///
/// Equally, a real fall is brief. Requiring a long unbroken run of `FALL`
/// would miss the event it exists to catch, because the glove may report
/// `FALL` once and then `NORMAL` from the floor.
///
/// So the rule is a **vote inside a short window**: at least
/// [requiredHits] danger-level classifications, each at or above the user's
/// threshold, within [window]. Two readings in five seconds is hard to
/// produce by accident and easy to produce by falling.
///
/// ## What it deliberately does not do
///
/// It does not dispatch. It reports that a countdown should start, and the
/// emergency screen runs its usual cancellable countdown -- the same one a
/// manual SOS gets. Nothing here shortens the window in which a woman can say
/// "I'm fine".
class GloveThreatDetector {
  GloveThreatDetector({
    this.requiredHits = 2,
    this.window = const Duration(seconds: 5),
    this.cooldown = const Duration(minutes: 2),
  });

  /// How many qualifying readings are needed inside [window].
  final int requiredHits;

  /// How far back a reading still counts toward the vote.
  final Duration window;

  /// How long to stay quiet after firing.
  ///
  /// Without it, the readings that triggered an alarm are still inside the
  /// window a second later and would trigger it again the moment the user
  /// cancelled -- turning one fall into an argument with the phone.
  final Duration cooldown;

  final List<DateTime> _hits = [];
  DateTime? _firedAt;

  /// Only this level auto-triggers.
  ///
  /// `FALL` is the one class in the trained set that describes something that
  /// has already gone wrong. `SUDDEN_MOVEMENT` maps to elevated and is left
  /// out on purpose: it is the class most likely to be produced by ordinary
  /// handling, and the cost of being wrong is a false alarm sent to someone's
  /// emergency contacts. Raising it to auto-dispatch is a product decision
  /// that should be made with data, not assumed here.
  static const triggeringLevel = ThreatLevel.danger;

  /// Feeds one classification in and reports whether an alarm should start.
  ///
  /// [now] is injected so tests do not have to sleep.
  bool shouldTrigger(
    GloveClassification classification, {
    required double threshold,
    required DateTime now,
  }) {
    // Below the user's sensitivity, or not the kind of movement that raises
    // an alarm at all: not a hit, and it does not disturb the ones already
    // counted.
    if (classification.threatLevel != triggeringLevel) return false;
    if (classification.confidence < threshold) return false;

    final firedAt = _firedAt;
    if (firedAt != null && now.difference(firedAt) < cooldown) return false;

    _hits
      ..removeWhere((hit) => now.difference(hit) > window)
      ..add(now);

    if (_hits.length < requiredHits) return false;

    _firedAt = now;
    _hits.clear();
    return true;
  }

  /// Forgets everything: used when the glove disconnects, so readings from
  /// before a dropout cannot combine with readings after it into a vote that
  /// never actually happened inside one window.
  void reset() {
    _hits.clear();
    _firedAt = null;
  }

  /// Visible for tests and for a future "why did it fire" diagnostic.
  int get pendingHits => _hits.length;
}
