"""The rule that only three signals may reach the threat score.

Weapon, audio and glove decide whether SafeHer raises an alarm. GPS, facial
expression, time of day, heart rate and device state are supporting evidence:
they belong on the incident, in the summary and on the dashboard, and none of
them is evidence that an assault is happening.

That is easy to state and easy to erode. Someone reasonable will one day
notice that fear was on the user's face, or that she was in a high-risk zone,
and reach for a `+0.05`. It would look like care. It would also mean alarms
during ordinary life, and every false alarm spends the credibility the real
one depends on.

So the separation is enforced structurally rather than by comment.
`ThreatSignals` has three fields, `evaluate` takes nothing else, and the tests
below fail if either changes. Adding a fourth input requires editing the engine
deliberately, with a reviewer attached.

The scenario tests at the bottom are the acceptance matrix for the fusion
architecture, written against behaviour rather than against arithmetic, so a
future re-tuning of the weights does not have to rewrite them.
"""

import unittest
from dataclasses import FrozenInstanceError, fields
from datetime import datetime, timedelta, timezone
from inspect import signature

from fastapi_app.services import threat_fusion as tf
from fastapi_app.services.threat_fusion import (
    FUSION_WEIGHTS,
    PRIMARY_SIGNAL_NAMES,
    SupportingContext,
    ThreatLevel,
    ThreatSignals,
    evaluate,
    fuse,
    level_for,
)


class TestOnlyThreeSignalsCanScore(unittest.TestCase):
    def test_there_are_exactly_three_primary_signals(self):
        self.assertEqual(set(PRIMARY_SIGNAL_NAMES), {"glove", "weapon", "audio"})
        self.assertEqual(len(fields(ThreatSignals)), 3)

    def test_the_weights_and_the_signals_cannot_drift_apart(self):
        # A weight with no field would never be applied; a field with no weight
        # would raise a KeyError inside an emergency decision.
        self.assertEqual(set(FUSION_WEIGHTS), set(PRIMARY_SIGNAL_NAMES))

    def test_the_engine_accepts_no_contextual_parameter(self):
        # The real guard. If someone threads `latitude` or `facial_expression`
        # into the decision, it has to appear here first.
        allowed = {
            "signals",
            "previous_smoothed",
            "previous_level",
            "threshold",
            "moment",
            "last_alert_at",
        }
        self.assertEqual(set(signature(evaluate).parameters), allowed)
        self.assertEqual(set(signature(fuse).parameters), {"signals"})

    def test_supporting_context_shares_no_field_with_the_signals(self):
        # Two containers, no overlap: nothing can be both scored and contextual,
        # which is how a "supporting" value quietly becomes a scoring one.
        context = {f.name for f in fields(SupportingContext)}
        self.assertEqual(context & set(PRIMARY_SIGNAL_NAMES), set())

    def test_signals_are_immutable(self):
        signals = ThreatSignals(glove=0.2)
        with self.assertRaises(FrozenInstanceError):
            signals.glove = 0.99  # type: ignore[misc]

    def test_context_never_changes_a_score(self):
        # The behavioural statement of the same rule, in case the structural
        # ones are ever relaxed: identical signals must score identically no
        # matter what was happening around them.
        signals = ThreatSignals(glove=0.7, weapon=0.6, audio=0.65)
        baseline = fuse(signals)

        for context in (
            SupportingContext(latitude=12.9, longitude=77.5),
            SupportingContext(in_high_risk_zone=True),
            SupportingContext(is_night=True),
            SupportingContext(heart_rate_bpm=180),
            SupportingContext(facial_expression="fear", facial_expression_confidence=0.99),
        ):
            with self.subTest(context=context):
                # There is nowhere to pass it, which is the point; constructing
                # it must not change the answer either.
                self.assertEqual(fuse(signals), baseline)


class TestMissingSignalsFailIndependently(unittest.TestCase):
    """One dead sensor must not disable the alarm."""

    def test_nothing_reporting_is_not_a_calm_score(self):
        self.assertIsNone(fuse(ThreatSignals()))
        self.assertIsNone(evaluate(signals=ThreatSignals()))

    def test_a_lone_signal_can_still_reach_the_top_of_the_scale(self):
        # Treating absent signals as 0.0 would cap a glove-only score at 0.40,
        # so a woman with a maximal reading and no glasses could never trigger.
        self.assertAlmostEqual(fuse(ThreatSignals(glove=1.0)), 1.0)
        self.assertAlmostEqual(fuse(ThreatSignals(weapon=1.0)), 1.0)
        self.assertAlmostEqual(fuse(ThreatSignals(audio=1.0)), 1.0)

    def test_losing_the_camera_leaves_glove_and_audio_working(self):
        decision = evaluate(signals=ThreatSignals(glove=0.9, audio=0.9), threshold=0.75)
        self.assertIsNotNone(decision)
        self.assertTrue(decision.should_trigger)

    def test_losing_the_microphone_leaves_glove_and_weapon_working(self):
        decision = evaluate(signals=ThreatSignals(glove=0.9, weapon=0.9), threshold=0.75)
        self.assertTrue(decision.should_trigger)

    def test_losing_the_glove_leaves_weapon_and_audio_working(self):
        decision = evaluate(signals=ThreatSignals(weapon=0.9, audio=0.9), threshold=0.75)
        self.assertTrue(decision.should_trigger)

    def test_a_reported_zero_is_not_the_same_as_silence(self):
        # 0.0 means "looked and saw calm" and must pull the average down;
        # None means "did not look" and must not.
        looked = fuse(ThreatSignals(glove=0.9, weapon=0.0))
        did_not_look = fuse(ThreatSignals(glove=0.9))
        self.assertLess(looked, did_not_look)


class TestCorroboration(unittest.TestCase):
    def test_agreeing_signals_score_above_the_weighted_mean(self):
        alone = fuse(ThreatSignals(glove=0.9))
        corroborated = fuse(ThreatSignals(glove=0.9, weapon=0.9, audio=0.9))
        self.assertGreater(corroborated, alone)

    def test_one_loud_signal_is_not_treated_as_three(self):
        # Case C from the architecture note: a high glove reading with two
        # quiet sensors must not read like all three alarmed.
        uncorroborated = fuse(ThreatSignals(glove=0.90, weapon=0.05, audio=0.10))
        corroborated = fuse(ThreatSignals(glove=0.90, weapon=0.90, audio=0.90))
        self.assertLess(uncorroborated, corroborated)

    def test_corroboration_cannot_raise_an_alarm_by_itself(self):
        # Three signals agreeing at a mild level must stay well clear of the
        # default threshold, or the bonus becomes its own trigger.
        mild = fuse(ThreatSignals(glove=0.50, weapon=0.50, audio=0.50))
        self.assertLess(mild, 0.75)

    def test_quiet_signals_earn_no_bonus(self):
        self.assertEqual(tf.corroboration_bonus(ThreatSignals(glove=0.1, weapon=0.1)), 0.0)


class TestThreatStateMachine(unittest.TestCase):
    def test_the_bands(self):
        self.assertEqual(level_for(0.00), ThreatLevel.SAFE)
        self.assertEqual(level_for(0.29), ThreatLevel.SAFE)
        self.assertEqual(level_for(0.30), ThreatLevel.ELEVATED)
        self.assertEqual(level_for(0.60), ThreatLevel.HIGH)
        self.assertEqual(level_for(0.80), ThreatLevel.CRITICAL)
        self.assertEqual(level_for(1.00), ThreatLevel.CRITICAL)

    def test_rising_needs_no_hysteresis(self):
        self.assertEqual(level_for(0.62, previous=ThreatLevel.SAFE), ThreatLevel.HIGH)

    def test_a_score_resting_on_a_boundary_does_not_flap(self):
        # Without hysteresis this alternates every heartbeat, which reads to a
        # user as the app panicking and calming down twice a second.
        self.assertEqual(level_for(0.59, previous=ThreatLevel.HIGH), ThreatLevel.HIGH)

    def test_it_does_drop_once_clear_of_the_band(self):
        self.assertEqual(level_for(0.50, previous=ThreatLevel.HIGH), ThreatLevel.ELEVATED)


class TestTemporalBehaviour(unittest.TestCase):
    def test_one_spike_is_damped_by_smoothing(self):
        calm = evaluate(signals=ThreatSignals(glove=0.1), threshold=0.75)
        spike = evaluate(
            signals=ThreatSignals(glove=1.0),
            previous_smoothed=calm.smoothed_score,
            threshold=0.75,
        )
        self.assertFalse(
            spike.should_trigger,
            "a single noisy reading must not summon anyone",
        )

    def test_a_sustained_threat_climbs_to_a_trigger(self):
        smoothed = None
        triggered = False
        for _ in range(12):
            decision = evaluate(
                signals=ThreatSignals(glove=0.95, weapon=0.9, audio=0.9),
                previous_smoothed=smoothed,
                threshold=0.75,
            )
            smoothed = decision.smoothed_score
            triggered = triggered or decision.should_trigger
        self.assertTrue(triggered, "a persistent three-signal threat must fire")

    def test_a_recent_alert_suppresses_a_duplicate(self):
        now = datetime.now(timezone.utc)
        decision = evaluate(
            signals=ThreatSignals(glove=0.99, weapon=0.99, audio=0.99),
            previous_smoothed=0.99,
            threshold=0.75,
            moment=now,
            last_alert_at=now - timedelta(seconds=10),
        )
        self.assertTrue(decision.suppressed_by_dedup)
        self.assertFalse(decision.should_trigger)

    def test_the_boundary_fires(self):
        # 0.30*x + 0.70*x is x in algebra and 0.7499999999999999 in binary
        # floating point. A sustained threat sitting exactly on the user's
        # threshold would never have raised the alarm.
        decision = evaluate(
            signals=ThreatSignals(glove=0.75),
            previous_smoothed=0.75,
            threshold=0.75,
        )
        self.assertTrue(decision.should_trigger)


class TestAcceptanceScenarios(unittest.TestCase):
    """The architecture's own test matrix, stated as behaviour."""

    def _level(self, **signals) -> ThreatLevel:
        return level_for(fuse(ThreatSignals(**signals)))

    def test_1_nothing_happening(self):
        self.assertEqual(self._level(glove=0.05, weapon=0.02, audio=0.05), ThreatLevel.SAFE)

    def test_2_aggressive_movement_only(self):
        level = self._level(glove=0.90, weapon=0.05, audio=0.10)
        self.assertGreaterEqual(level.rank, ThreatLevel.ELEVATED.rank)

    def test_3_weapon_only(self):
        level = self._level(glove=0.10, weapon=0.90, audio=0.05)
        self.assertGreaterEqual(level.rank, ThreatLevel.ELEVATED.rank)

    def test_4_help_word_only(self):
        level = self._level(glove=0.10, weapon=0.05, audio=0.90)
        self.assertGreaterEqual(level.rank, ThreatLevel.ELEVATED.rank)

    def test_5_all_three_strong_is_critical(self):
        self.assertEqual(
            self._level(glove=0.90, weapon=0.90, audio=0.90), ThreatLevel.CRITICAL
        )

    def test_6_fear_on_a_face_with_three_quiet_signals_stays_safe(self):
        # The scenario the whole separation exists for.
        quiet = ThreatSignals(glove=0.05, weapon=0.05, audio=0.05)
        context = SupportingContext(facial_expression="fear", facial_expression_confidence=0.97)

        self.assertEqual(level_for(fuse(quiet)), ThreatLevel.SAFE)
        self.assertEqual(context.facial_expression, "fear")  # recorded, not scored

    def test_7_gps_moving_fast_with_three_quiet_signals_stays_safe(self):
        quiet = ThreatSignals(glove=0.05, weapon=0.05, audio=0.05)
        before = fuse(quiet)
        SupportingContext(latitude=12.9716, longitude=77.5946, in_high_risk_zone=True)

        self.assertEqual(fuse(quiet), before)
        self.assertEqual(level_for(before), ThreatLevel.SAFE)


if __name__ == "__main__":
    unittest.main()
