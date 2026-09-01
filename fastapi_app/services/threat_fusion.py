"""The one authoritative threat fusion engine — SRS §6.2, FR-EMG-02.

**Why this exists.** `SRS.md` specifies an auto-SOS at a threat score of 0.75
(FR-EMG-02, a MUST) and an algorithm to reach that score (§6.2). Until this
landed neither was implemented: `/alerts/heartbeat` accepted a score, mapped it
to a colour band and stored it, and nothing ever acted on it. Worse, the mobile
app shipped a "threat threshold" slider that wrote to Hive and was read by
nothing — a user could set it to 60% and reasonably believe SafeHer would raise
the alarm for her.

## Exactly three signals decide the score

    glove   XGBoost over the Smart Glove's accelerometer/gyroscope
    weapon  YOLOv8-nano weapon detection from the Smart Glasses' camera
    audio   CNN+LSTM threat/help-word detection from the glasses' microphone

**Nothing else may enter the score.** Not GPS, not time of day, not facial
expression, not heart rate, not whether a camera happens to be streaming.
Those are *supporting evidence*: they belong to the incident record, the
dashboard and the AI summary, and they are carried here by
[SupportingContext], which exists precisely so there is somewhere to put them
that is visibly not the score.

That separation is enforced by construction rather than by convention.
[ThreatSignals] has three fields and [fuse] accepts nothing else, so adding a
fourth input to the score is not something a future change can do by accident
— it requires editing this module, which is the point.

## What changed on 2026-08-30, and why it is a deviation

SRS §6.2 also specifies *additive context boosters*: +0.10 at night, +0.05 in a
high-risk zone, +0.15 for a confident weapon. Those were implemented here and
are now removed from the score on the product owner's instruction, because each
is context rather than a threat signal, and a weapon booster on top of the
vision weight counted the same detection twice.

**This lowers scores at night and in high-risk zones compared with the previous
behaviour.** That is the intended consequence of the decision, not an oversight,
and it is recorded in `docs/SRS_STATUS.md` under deliberate deviations. Night
and zone are still captured on the incident — see [SupportingContext].

## What is still honest about this module

No trained model produces a weapon or audio score today: `ml_training/` holds
training scripts and no weights, and no Smart Glasses hardware exists. The
glove is the one real producer. So this engine is exercised end to end only by
the glove and by scores a caller supplies, and `threat_models.py` reports which
modalities are genuinely live rather than letting the UI imply three.
"""

from __future__ import annotations

from dataclasses import dataclass, fields
from datetime import datetime, timedelta, timezone
from enum import Enum
from typing import Optional

# ---------------------------------------------------------------------------
# Central configuration. Every weight and threshold the engine uses lives here
# and nowhere else, so tuning is one edit rather than a search across the app.
# ---------------------------------------------------------------------------

# Relative importance of the three primary signals, ordered by how ambiguous
# each one is.
#
# **This deliberately inverts SRS §6.2's 0.40 motion / 0.35 audio / 0.25
# vision.** Those weights describe generic modalities, and under them a knife
# detected at 0.90 confidence scored 0.28 — SAFE — because the least ambiguous
# signal in the system carried the least weight and two quiet sensors averaged
# it away. That was found by the acceptance matrix, not by reading the code.
#
# Under the three-signal architecture the signals are specific detectors with
# very different ambiguity:
#
#   weapon  A YOLO detection is a discrete claim about an object in view. A
#           knife is a knife. Least ambiguous, so the largest weight.
#   audio   A recognised help or threat word is a deliberate human utterance.
#           Strong, but speech is noisy and a classifier can mishear.
#   glove   Motion is the most ambiguous of the three. A FALL can be a dropped
#           glove or a sleeve caught on a door, which is exactly why the
#           on-device rule already demands two hits in five seconds.
#
# These are a considered starting point, not a validated optimum. Nothing has
# measured them against real incidents, because there are none: two of the
# three producers do not exist yet.
#
# Note this costs the glove nothing today. It is currently the only reporting
# signal, and `fuse` renormalises over whatever reported — with the glove
# alone the weight cancels and the score is the glove score, whatever the
# weight says.
FUSION_WEIGHTS: dict[str, float] = {
    "weapon": 0.40,
    "audio": 0.35,
    "glove": 0.25,
}

# A weighted mean answers "how alarming is the situation on average", which is
# the wrong question when one sensor is certain and the others simply have
# nothing to say. A knife in view is not made safe by a calm wrist.
#
# So the score never falls below this fraction of the strongest single signal.
# At 0.5, one maximal signal alone reaches 0.50 — enough to raise the level and
# start watching, nowhere near the 0.75 default trigger, which still needs
# either corroboration or a sustained reading to reach.
SOLO_SIGNAL_RETENTION = 0.50

# SRS §6.2: smoothed(t) = 0.30*raw(t) + 0.70*smoothed(t-1)
EMA_ALPHA = 0.30

# SRS FR-EMG-02 / §6.2 default when a user has expressed no preference.
DEFAULT_THREAT_THRESHOLD = 0.75

# SRS §6.2 says "suppress re-trigger for 120 seconds"; §8.2 and TC-EMG-05 both
# say 60. The longer window is the safer reading of the conflict — a suppressed
# duplicate is a nuisance, while a second dispatch spams every contact of a
# woman already in an emergency — so 120 is used and the discrepancy recorded.
DEDUP_WINDOW_SECONDS = 120

# Two independent signals agreeing is stronger evidence than one shouting.
# A weighted sum alone cannot express that: glove 0.9 alone and glove 0.9 with
# weapon 0.9 differ only by the weapon's weight. This adds a small bonus when
# more than one signal is independently above `CORROBORATION_FLOOR`.
#
# Deliberately small, and deliberately incapable of raising the alarm alone:
# the maximum bonus cannot lift a score from below any threshold band to
# CRITICAL on its own.
CORROBORATION_FLOOR = 0.50
CORROBORATION_BONUS_PER_EXTRA_SIGNAL = 0.05

# Threat bands. Starting values, not validated.
LEVEL_THRESHOLDS: dict[str, float] = {
    "elevated": 0.30,
    "high": 0.60,
    "critical": 0.80,
}

# Hysteresis: a score must fall this far below a band's floor before the state
# drops out of it. Without it a score hovering at a boundary flaps between
# levels every heartbeat, which reads to a user as the app panicking and
# calming down twice a second.
LEVEL_EXIT_MARGIN = 0.05

# Smoothing a constant value should return it unchanged — 0.30*x + 0.70*x is x
# — but in binary floating point it does not: at x = 0.75 the result is
# 0.7499999999999999, which is *below* a 0.75 threshold compared with `>=`. A
# sustained threat sitting exactly at the user's setting would never have
# raised the alarm. Found by a boundary test.
SCORE_EPSILON = 1e-9


class ThreatLevel(str, Enum):
    """The band a fused score falls in. Ordered."""

    SAFE = "safe"
    ELEVATED = "elevated"
    HIGH = "high"
    CRITICAL = "critical"

    @property
    def rank(self) -> int:
        return _LEVEL_ORDER.index(self)


_LEVEL_ORDER = [
    ThreatLevel.SAFE,
    ThreatLevel.ELEVATED,
    ThreatLevel.HIGH,
    ThreatLevel.CRITICAL,
]


@dataclass(frozen=True)
class ThreatSignals:
    """The only inputs that may affect the fused score.

    Three fields, and a test asserts there are exactly three. Adding a fourth
    means editing this class, which is a deliberate act with a reviewer
    attached — as opposed to threading a `latitude` through a function call and
    quietly changing what "threat" means.

    `None` means *this signal did not report*, which is a different fact from
    0.0 meaning *it reported and saw calm*. Conflating them is the dangerous
    direction: see [fuse].
    """

    glove: Optional[float] = None
    weapon: Optional[float] = None
    audio: Optional[float] = None

    @property
    def reporting(self) -> dict[str, float]:
        return {
            name: value
            for name, value in (
                ("glove", self.glove),
                ("weapon", self.weapon),
                ("audio", self.audio),
            )
            if value is not None
        }

    @property
    def has_any(self) -> bool:
        return bool(self.reporting)


@dataclass(frozen=True)
class SupportingContext:
    """Everything that describes an incident but does not score it.

    This exists so that context has an obvious home that is visibly not the
    threat score. Facial expression, location, time of day and heart rate are
    all real and all worth recording — on the incident, in the summary, on the
    dashboard — and none of them is evidence that an assault is happening.

    A racing pulse is evidence of running for a bus. Fear on a face is evidence
    of a startling noise. Night is evidence of night. Acting on any of them
    would raise alarms during ordinary life, and every false alarm spends the
    credibility the real one depends on.
    """

    latitude: Optional[float] = None
    longitude: Optional[float] = None
    in_high_risk_zone: bool = False
    is_night: bool = False
    heart_rate_bpm: Optional[float] = None
    facial_expression: Optional[str] = None
    facial_expression_confidence: Optional[float] = None
    detected_weapon_label: Optional[str] = None
    detected_audio_label: Optional[str] = None


def is_night(moment: datetime) -> bool:
    """SRS §6.2 night window: 22:00–05:59, which wraps midnight.

    Retained for [SupportingContext]: it is recorded on the incident, and no
    longer touches the score.
    """
    return moment.hour >= 22 or moment.hour < 6


def fuse(signals: ThreatSignals) -> Optional[float]:
    """Weighted fusion over whichever of the three signals actually reported.

    Returns None when nothing reported — distinct from 0.0, which would claim
    all three looked and saw calm.

    Two rules shape the arithmetic, and both exist because of a way this got
    it wrong before.

    **A lone strong signal is not averaged away.** The score never falls below
    [SOLO_SIGNAL_RETENTION] of the loudest single reading, because a weighted
    mean answers "how alarming on average" — and a knife in view is not made
    safe by a calm wrist.

    **Absent signals are excluded and the remaining weights renormalised.**
    Treating a missing signal as 0.0 fails silently and dangerously: with no
    weapon score the ceiling would be 0.40 + 0.35 = 0.75, so a woman with
    maximal glove *and* maximal audio distress would only just reach the
    default threshold; with the glove alone the ceiling is 0.40 and the alarm
    could never fire. A camera that was switched off would quietly disable
    auto-SOS. Renormalised, the score answers the only question the available
    data can: how threatening is what we can actually observe.
    """
    reporting = signals.reporting
    if not reporting:
        return None

    total_weight = sum(FUSION_WEIGHTS[name] for name in reporting)
    weighted = sum(FUSION_WEIGHTS[name] * value for name, value in reporting.items())
    mean = weighted / total_weight

    # The floor below. Without it a lone confident detection is averaged away
    # by sensors that saw nothing, which is how a visible weapon once scored
    # SAFE.
    floor = SOLO_SIGNAL_RETENTION * max(reporting.values())

    return min(1.0, max(mean, floor) + corroboration_bonus(signals))


def corroboration_bonus(signals: ThreatSignals) -> float:
    """Extra weight when independent signals agree — SRS-adjacent, §15.

    Two sensors on different limbs, watching different things, both alarmed is
    materially stronger evidence than one alarmed and two quiet. A weighted
    mean cannot say that on its own.

    Capped so it can never be the difference between calm and an emergency by
    itself: with three corroborating signals the bonus is 0.10, and a set of
    signals that quiet still scores far below any threshold.
    """
    agreeing = sum(1 for value in signals.reporting.values() if value >= CORROBORATION_FLOOR)
    if agreeing < 2:
        return 0.0
    return CORROBORATION_BONUS_PER_EXTRA_SIGNAL * (agreeing - 1)


def smooth(*, raw: float, previous: Optional[float]) -> float:
    """Exponential moving average, SRS §6.2.

    A first reading has nothing to smooth against, and seeding at zero would
    halve a genuine spike on the very first sample — the one most likely to be
    the emergency. So the first raw value is taken as-is.
    """
    if previous is None:
        return raw
    return (EMA_ALPHA * raw) + ((1.0 - EMA_ALPHA) * previous)


def level_for(score: float, *, previous: Optional[ThreatLevel] = None) -> ThreatLevel:
    """Band a score, with hysteresis on the way down.

    Rising uses the plain thresholds. Falling requires the score to drop
    [LEVEL_EXIT_MARGIN] below the band's floor, so a score resting on a
    boundary does not flap between two levels on every heartbeat.
    """
    if score >= LEVEL_THRESHOLDS["critical"]:
        return ThreatLevel.CRITICAL
    if score >= LEVEL_THRESHOLDS["high"]:
        candidate = ThreatLevel.HIGH
    elif score >= LEVEL_THRESHOLDS["elevated"]:
        candidate = ThreatLevel.ELEVATED
    else:
        candidate = ThreatLevel.SAFE

    if previous is None or candidate.rank >= previous.rank:
        return candidate

    # Falling: stay in the previous band until clear of its floor by the margin.
    floor = LEVEL_THRESHOLDS.get(previous.value)
    if floor is not None and score >= (floor - LEVEL_EXIT_MARGIN):
        return previous
    return candidate


@dataclass
class FusionDecision:
    """The outcome of one heartbeat, and why."""

    signals: ThreatSignals
    raw_score: float
    smoothed_score: float
    level: ThreatLevel
    threshold: float
    should_trigger: bool
    suppressed_by_dedup: bool = False

    @property
    def reason(self) -> str:
        contributing = ", ".join(
            f"{name} {value:.2f}" for name, value in sorted(self.signals.reporting.items())
        ) or "no signal reported"
        if self.suppressed_by_dedup:
            return (
                f"score {self.smoothed_score:.2f} cleared the {self.threshold:.2f} "
                f"threshold but an alert fired less than {DEDUP_WINDOW_SECONDS}s ago "
                f"({contributing})"
            )
        if self.should_trigger:
            return (
                f"score {self.smoothed_score:.2f} reached the {self.threshold:.2f} "
                f"threshold ({contributing})"
            )
        return (
            f"score {self.smoothed_score:.2f} is below the {self.threshold:.2f} "
            f"threshold ({contributing})"
        )


def evaluate(
    *,
    signals: ThreatSignals,
    previous_smoothed: Optional[float] = None,
    previous_level: Optional[ThreatLevel] = None,
    threshold: float = DEFAULT_THREAT_THRESHOLD,
    moment: Optional[datetime] = None,
    last_alert_at: Optional[datetime] = None,
) -> Optional[FusionDecision]:
    """Decides whether this heartbeat should raise the alarm.

    Returns None when no signal reported at all — there is nothing to decide,
    and inventing a 0.0 would claim three sensors looked and saw calm.

    Takes [ThreatSignals] and nothing else that could reach the score.
    [SupportingContext] is deliberately not a parameter: this function has no
    use for it, and having no place to put it is what stops it being used.
    """
    if not signals.has_any:
        return None

    moment = moment or datetime.now(timezone.utc)

    raw = fuse(signals)
    assert raw is not None  # has_any guarantees it
    smoothed = smooth(raw=raw, previous=previous_smoothed)
    level = level_for(smoothed, previous=previous_level)

    crossed = smoothed >= (threshold - SCORE_EPSILON)
    suppressed = False
    if crossed and last_alert_at is not None:
        # Both instants normalised to UTC: comparing a naive database
        # timestamp against an aware one raises, and doing that inside an
        # emergency path would turn a dispatch into a 500.
        last = last_alert_at if last_alert_at.tzinfo else last_alert_at.replace(tzinfo=timezone.utc)
        suppressed = (moment - last) < timedelta(seconds=DEDUP_WINDOW_SECONDS)

    return FusionDecision(
        signals=signals,
        raw_score=raw,
        smoothed_score=smoothed,
        level=level,
        threshold=threshold,
        should_trigger=crossed and not suppressed,
        suppressed_by_dedup=suppressed,
    )


# --- the architectural invariant, available to callers and tests -----------

PRIMARY_SIGNAL_NAMES: tuple[str, ...] = tuple(f.name for f in fields(ThreatSignals))
"""The signals allowed to affect the score. Asserted by a test against both
[FUSION_WEIGHTS] and [ThreatSignals], so the three cannot drift apart."""
