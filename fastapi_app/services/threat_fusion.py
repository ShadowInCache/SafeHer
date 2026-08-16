"""Threat fusion and the auto-SOS decision — SRS §6.2, FR-EMG-02.

**Why this exists.** `SRS.md` specifies an auto-SOS at a threat score of
0.75 (FR-EMG-02, a MUST) and an algorithm to reach that score (§6.2). Until
now neither was implemented. `/alerts/heartbeat` accepted a score, mapped it
to a colour band and stored it; nothing ever acted on it. Worse, the mobile
app has shipped a "threat threshold" slider on the Profile screen since
early on — a control that wrote to Hive and was read by nothing. A user
could set it to 60% and reasonably believe SafeHer would raise the alarm for
her. It would not have.

**What is honest about this module.** The three modality scores in §6.2
(motion, audio, vision) come from firmware that does not exist yet, so
[fuse] cannot be exercised end to end. What it *can* do is be correct and
ready for the moment a score arrives, and act on the scores SafeHer already
receives today — the phone posts one on every heartbeat. So the decision
path (smoothing, boosters, threshold, deduplication) is live now, and the
weighted fusion is unit-tested against §6.2 rather than left unwritten.

Every constant here is quoted from the SRS rather than chosen.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Optional

# SRS §6.2: threat_score = 0.40*motion + 0.35*audio + 0.25*vision
MOTION_WEIGHT = 0.40
AUDIO_WEIGHT = 0.35
VISION_WEIGHT = 0.25

# SRS §6.2: smoothed(t) = 0.30*raw(t) + 0.70*smoothed(t-1)
EMA_ALPHA = 0.30

# SRS §6.2 context boosters (additive).
NIGHT_BOOST = 0.10
HIGH_RISK_ZONE_BOOST = 0.05
WEAPON_BOOST = 0.15
WEAPON_CONFIDENCE_FLOOR = 0.70

# SRS §6.2: "night hours" is `hour in range(22, 6)`. That expression is empty
# in Python and would boost nothing, so the intent is read as the wrapping
# window it describes: 22:00 through 05:59.
NIGHT_START_HOUR = 22
NIGHT_END_HOUR = 6

# SRS FR-EMG-02 / §6.2 default when a user has expressed no preference.
DEFAULT_THREAT_THRESHOLD = 0.75

# SRS §6.2 says "suppress re-trigger for 120 seconds"; §8.2 and TC-EMG-05
# both say 60. The longer window is the safer reading of a conflict — a
# suppressed duplicate is a nuisance, while a second dispatch spams every
# contact of a woman already in an emergency — so 120 is used and the
# discrepancy is recorded here rather than silently resolved.
DEDUP_WINDOW_SECONDS = 120

# Smoothing a constant value should return it unchanged -- 0.30*x + 0.70*x
# is x -- but in binary floating point it does not: at x = 0.75 the result
# is 0.7499999999999999. Compared with `>=` that is *below* a 0.75
# threshold, so a sustained threat sitting exactly at the user's setting
# would never raise the alarm. The SRS says "score >= threshold" and means
# the boundary to fire, so the comparison is given a tolerance far smaller
# than any meaningful difference in score.
SCORE_EPSILON = 1e-9


def fuse(*, motion: float, audio: float, vision: float) -> float:
    """Weighted multi-modal threat score, SRS §6.2.

    Not reachable end to end yet: nothing produces the three inputs until
    the glove and glasses firmware exists. Written and tested now so that
    the arithmetic is not the unknown when they do.
    """
    return (MOTION_WEIGHT * motion) + (AUDIO_WEIGHT * audio) + (VISION_WEIGHT * vision)


def smooth(*, raw: float, previous: Optional[float]) -> float:
    """Exponential moving average, SRS §6.2.

    A first reading has nothing to smooth against, and seeding it at zero
    would halve a genuine spike on the very first sample — the one most
    likely to be the emergency. So the first raw value is taken as-is.
    """
    if previous is None:
        return raw
    return (EMA_ALPHA * raw) + ((1.0 - EMA_ALPHA) * previous)


def is_night(moment: datetime) -> bool:
    """SRS §6.2 night window: 22:00–05:59, which wraps midnight."""
    return moment.hour >= NIGHT_START_HOUR or moment.hour < NIGHT_END_HOUR


def apply_boosters(
    score: float,
    *,
    moment: datetime,
    in_high_risk_zone: bool = False,
    weapon_confidence: float = 0.0,
) -> float:
    """Additive context boosters, SRS §6.2.

    Clamped to 1.0: three boosters on an already-high score would otherwise
    produce a number above the scale everything downstream assumes.
    """
    boosted = score
    if is_night(moment):
        boosted += NIGHT_BOOST
    if in_high_risk_zone:
        boosted += HIGH_RISK_ZONE_BOOST
    if weapon_confidence > WEAPON_CONFIDENCE_FLOOR:
        boosted += WEAPON_BOOST
    return min(boosted, 1.0)


@dataclass
class FusionDecision:
    """The outcome of one heartbeat, and why."""

    raw_score: float
    smoothed_score: float
    boosted_score: float
    threshold: float
    should_trigger: bool
    suppressed_by_dedup: bool = False

    @property
    def reason(self) -> str:
        if self.suppressed_by_dedup:
            return (
                f"score {self.boosted_score:.2f} cleared the {self.threshold:.2f} "
                f"threshold but an alert fired less than {DEDUP_WINDOW_SECONDS}s ago"
            )
        if self.should_trigger:
            return f"score {self.boosted_score:.2f} reached the {self.threshold:.2f} threshold"
        return f"score {self.boosted_score:.2f} is below the {self.threshold:.2f} threshold"


def evaluate(
    *,
    raw_score: float,
    previous_smoothed: Optional[float],
    threshold: float = DEFAULT_THREAT_THRESHOLD,
    moment: Optional[datetime] = None,
    in_high_risk_zone: bool = False,
    weapon_confidence: float = 0.0,
    last_alert_at: Optional[datetime] = None,
) -> FusionDecision:
    """Decides whether this heartbeat should raise the alarm.

    Ordering follows §6.2 and matters: smoothing damps a single noisy
    reading, and boosters are applied to the smoothed value so that a
    night-time context cannot by itself promote one bad sample into an
    emergency.
    """
    moment = moment or datetime.now(timezone.utc)

    smoothed = smooth(raw=raw_score, previous=previous_smoothed)
    boosted = apply_boosters(
        smoothed,
        moment=moment,
        in_high_risk_zone=in_high_risk_zone,
        weapon_confidence=weapon_confidence,
    )

    crossed = boosted >= (threshold - SCORE_EPSILON)
    suppressed = False
    if crossed and last_alert_at is not None:
        # Both instants are normalised to UTC: a naive timestamp from the
        # database compared against an aware one raises, and doing that
        # inside an emergency path would turn a dispatch into a 500.
        last = last_alert_at if last_alert_at.tzinfo else last_alert_at.replace(tzinfo=timezone.utc)
        suppressed = (moment - last) < timedelta(seconds=DEDUP_WINDOW_SECONDS)

    return FusionDecision(
        raw_score=raw_score,
        smoothed_score=smoothed,
        boosted_score=boosted,
        threshold=threshold,
        should_trigger=crossed and not suppressed,
        suppressed_by_dedup=suppressed,
    )

# --- partial sensor coverage ---------------------------------------------
#
# The three modalities come from two different wearables. The glasses can be
# off, out of battery or out of range while the glove is still transmitting,
# so a score for every modality is the exception rather than the rule.
#
# Treating a missing modality as 0.0 is the dangerous reading, and it fails
# silently: with no vision score the maximum reachable value is 0.40 + 0.35
# = 0.75, so a woman with maximal motion *and* maximal audio distress only
# just reaches the default threshold. With only the glove, the ceiling is
# 0.40 and the alarm can never fire at all. A missing camera would quietly
# disable auto-SOS.
#
# So absent modalities are excluded and the remaining weights renormalised:
# the score means "how threatening is what we can actually observe", which
# is the only question the available data can answer.

# Heart rate is not in SRS §6.2, and the §9.1 glove BOM has no pulse sensor
# -- the "heartbeat" in §7.3 is a 30-second MQTT keepalive, not a pulse. It
# is carried here as a context booster rather than a fourth fusion weight,
# so §6.2's arithmetic stays exactly as specified and verifiable. Revisit if
# the requirement is amended to give it a weight.
TACHYCARDIA_BPM = 120
HEART_RATE_BOOST = 0.05


def fuse_available(
    *,
    motion: Optional[float] = None,
    audio: Optional[float] = None,
    vision: Optional[float] = None,
) -> Optional[float]:
    """Weighted fusion over whichever modalities actually reported.

    Returns None when nothing reported at all -- distinct from 0.0, which
    would mean "all three sensors looked and saw calm".
    """
    present = [
        (MOTION_WEIGHT, motion),
        (AUDIO_WEIGHT, audio),
        (VISION_WEIGHT, vision),
    ]
    present = [(weight, value) for weight, value in present if value is not None]
    if not present:
        return None

    total_weight = sum(weight for weight, _ in present)
    return sum(weight * value for weight, value in present) / total_weight


def heart_rate_boost(bpm: Optional[float]) -> float:
    """Additive booster for a racing pulse.

    Deliberately small. An elevated heart rate is not evidence of an
    assault -- it is evidence of running for a bus -- so it can nudge a
    score that other sensors already find alarming, and cannot raise the
    alarm by itself.
    """
    if bpm is None:
        return 0.0
    return HEART_RATE_BOOST if bpm >= TACHYCARDIA_BPM else 0.0
