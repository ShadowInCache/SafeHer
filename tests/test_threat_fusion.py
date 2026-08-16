"""Auto-SOS and the fusion algorithm — SRS FR-EMG-02 and §6.2.

FR-EMG-02 is a MUST, and until now it was neither implemented nor honestly
recorded: the traceability matrix listed it as done against a router that
only ever stored the score it was given. The mobile app meanwhile shipped a
"threat threshold" slider that wrote to Hive and was read by nothing, so a
user could set it to 60% and reasonably believe SafeHer would raise the
alarm for her.

These tests pin the arithmetic against §6.2 line by line, and the decision
path against the acceptance criterion.
"""

from __future__ import annotations

import os
import unittest
from datetime import datetime, timedelta, timezone
from uuid import uuid4

os.environ["DATABASE_URL"] = "sqlite:///./test_safeher.db"
os.environ["ENABLE_MQTT_WORKER"] = "false"
os.environ["JWT_SECRET_KEY"] = "test-secret-key-change-me"
os.environ["LOG_LEVEL"] = "WARNING"

import httpx

from fastapi_app.db import init_db
from fastapi_app.main import app
from fastapi_app.services import threat_fusion as tf


class TestFusionArithmetic(unittest.TestCase):
    """SRS §6.2, quoted rather than paraphrased."""

    def test_the_weights_are_the_ones_the_srs_specifies(self):
        # 0.40*motion + 0.35*audio + 0.25*vision
        self.assertAlmostEqual(tf.fuse(motion=1.0, audio=0.0, vision=0.0), 0.40)
        self.assertAlmostEqual(tf.fuse(motion=0.0, audio=1.0, vision=0.0), 0.35)
        self.assertAlmostEqual(tf.fuse(motion=0.0, audio=0.0, vision=1.0), 0.25)
        # The weights are a partition, so a maximal reading is exactly 1.0.
        self.assertAlmostEqual(tf.fuse(motion=1.0, audio=1.0, vision=1.0), 1.0)

    def test_smoothing_follows_the_specified_ratio(self):
        # smoothed(t) = 0.30*raw(t) + 0.70*smoothed(t-1)
        self.assertAlmostEqual(tf.smooth(raw=1.0, previous=0.0), 0.30)
        self.assertAlmostEqual(tf.smooth(raw=0.0, previous=1.0), 0.70)

    def test_the_first_reading_is_not_smoothed_against_zero(self):
        # Seeding at zero would halve the very first spike -- which is the
        # one most likely to be the emergency.
        self.assertEqual(tf.smooth(raw=0.9, previous=None), 0.9)

    def test_the_night_window_wraps_midnight(self):
        # The SRS writes `hour in range(22, 6)`, which is empty in Python
        # and would boost nothing. The window it describes is 22:00-05:59.
        for hour in (22, 23, 0, 3, 5):
            self.assertTrue(tf.is_night(datetime(2026, 8, 17, hour)), hour)
        for hour in (6, 12, 21):
            self.assertFalse(tf.is_night(datetime(2026, 8, 17, hour)), hour)

    def test_boosters_are_additive_and_match_the_srs(self):
        noon = datetime(2026, 8, 17, 12)
        self.assertAlmostEqual(tf.apply_boosters(0.5, moment=noon), 0.5)
        self.assertAlmostEqual(tf.apply_boosters(0.5, moment=datetime(2026, 8, 17, 23)), 0.60)
        self.assertAlmostEqual(tf.apply_boosters(0.5, moment=noon, in_high_risk_zone=True), 0.55)
        self.assertAlmostEqual(tf.apply_boosters(0.5, moment=noon, weapon_confidence=0.8), 0.65)

    def test_a_weapon_at_or_below_the_floor_does_not_boost(self):
        # The SRS says `> 0.70`, not `>=`.
        noon = datetime(2026, 8, 17, 12)
        self.assertAlmostEqual(tf.apply_boosters(0.5, moment=noon, weapon_confidence=0.70), 0.5)

    def test_boosted_scores_stay_on_the_scale(self):
        # Three boosters on a high score would otherwise exceed 1.0 and
        # break every consumer that assumes a 0-1 range.
        score = tf.apply_boosters(
            0.95,
            moment=datetime(2026, 8, 17, 23),
            in_high_risk_zone=True,
            weapon_confidence=0.9,
        )
        self.assertLessEqual(score, 1.0)


class TestDecision(unittest.TestCase):
    NOON = datetime(2026, 8, 17, 12, tzinfo=timezone.utc)

    def test_the_default_threshold_is_the_one_fr_emg_02_names(self):
        self.assertEqual(tf.DEFAULT_THREAT_THRESHOLD, 0.75)

    def test_a_score_at_the_threshold_triggers(self):
        # "score >= 0.75" -- the boundary itself must fire, not just above.
        decision = tf.evaluate(raw_score=0.75, previous_smoothed=0.75, moment=self.NOON)
        self.assertTrue(decision.should_trigger)

    def test_a_score_below_the_threshold_does_not(self):
        decision = tf.evaluate(raw_score=0.5, previous_smoothed=0.5, moment=self.NOON)
        self.assertFalse(decision.should_trigger)

    def test_a_chosen_threshold_overrides_the_default(self):
        # The slider on the Profile screen is the point of this.
        decision = tf.evaluate(
            raw_score=0.6, previous_smoothed=0.6, threshold=0.55, moment=self.NOON
        )
        self.assertTrue(decision.should_trigger)

    def test_one_noisy_reading_does_not_raise_the_alarm(self):
        # The whole purpose of smoothing: a single 1.0 against a calm
        # history smooths to 0.3*1.0 + 0.7*0.1 = 0.37, well under 0.75.
        decision = tf.evaluate(raw_score=1.0, previous_smoothed=0.1, moment=self.NOON)
        self.assertFalse(decision.should_trigger)
        self.assertAlmostEqual(decision.smoothed_score, 0.37)

    def test_a_sustained_threat_does_raise_it(self):
        smoothed = None
        for _ in range(8):
            decision = tf.evaluate(raw_score=1.0, previous_smoothed=smoothed, moment=self.NOON)
            smoothed = decision.smoothed_score
        self.assertTrue(decision.should_trigger)

    def test_a_recent_automatic_alert_suppresses_a_second(self):
        # SRS §6.2 deduplication. Alerting every contact twice for one
        # emergency is worse than a missed duplicate.
        decision = tf.evaluate(
            raw_score=0.9,
            previous_smoothed=0.9,
            moment=self.NOON,
            last_alert_at=self.NOON - timedelta(seconds=30),
        )
        self.assertFalse(decision.should_trigger)
        self.assertTrue(decision.suppressed_by_dedup)
        self.assertIn("less than", decision.reason)

    def test_the_window_expires(self):
        decision = tf.evaluate(
            raw_score=0.9,
            previous_smoothed=0.9,
            moment=self.NOON,
            last_alert_at=self.NOON - timedelta(seconds=tf.DEDUP_WINDOW_SECONDS + 1),
        )
        self.assertTrue(decision.should_trigger)

    def test_a_naive_timestamp_does_not_crash_the_emergency_path(self):
        # The database hands back naive datetimes. Comparing one against an
        # aware `now` raises TypeError, and doing that here would turn a
        # dispatch into a 500 at the worst possible moment.
        decision = tf.evaluate(
            raw_score=0.9,
            previous_smoothed=0.9,
            moment=self.NOON,
            last_alert_at=datetime(2026, 8, 17, 11, 59, 30),  # naive
        )
        self.assertTrue(decision.suppressed_by_dedup)


class TestAutoSosEndToEnd(unittest.IsolatedAsyncioTestCase):
    """FR-EMG-02 through the API, with no user interaction at any point."""

    async def asyncSetUp(self):
        await init_db()
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://testserver"
        )
        email = f"autosos-{uuid4().hex}@safeherapp.com"
        await self.client.post(
            "/api/v1/auth/register",
            json={"email": email, "password": "TestPass123!", "full_name": "A", "role": "user"},
        )
        login = await self.client.post(
            "/api/v1/auth/login", json={"email": email, "password": "TestPass123!"}
        )
        self.headers = {"Authorization": f"Bearer {login.json()['access_token']}"}

    async def asyncTearDown(self):
        await self.client.aclose()

    async def _heartbeat(self, score: float) -> dict:
        response = await self.client.post(
            "/api/v1/alerts/heartbeat",
            headers=self.headers,
            json={
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "threat_score": score,
                "location": {"latitude": 12.85, "longitude": 77.68},
            },
        )
        self.assertEqual(response.status_code, 202, response.text)
        return response.json()

    async def test_the_endpoint_reports_its_auto_sos_decision(self):
        # Previously this endpoint stored a score and said nothing about
        # whether anything would be done with it.
        body = await self._heartbeat(10.0)

        self.assertIn("auto_sos", body)
        self.assertFalse(body["auto_sos"]["triggered"])
        self.assertEqual(body["auto_sos"]["threshold"], 0.75)

    async def test_a_calm_reading_raises_nothing(self):
        body = await self._heartbeat(5.0)

        self.assertFalse(body["auto_sos"]["triggered"])
        self.assertIn("below", body["auto_sos"]["reason"])

    async def test_a_sustained_threat_dispatches_without_a_single_tap(self):
        # The acceptance criterion for FR-EMG-02 is "zero user interaction
        # required". Nothing in this test touches an SOS button.
        for _ in range(10):
            body = await self._heartbeat(100.0)
            if body["auto_sos"]["triggered"]:
                break

        self.assertTrue(body["auto_sos"]["triggered"], body["auto_sos"])
        self.assertIn("incident_id", body["auto_sos"])

    async def test_the_incident_is_marked_as_system_raised(self):
        for _ in range(10):
            body = await self._heartbeat(100.0)
            if body["auto_sos"]["triggered"]:
                break
        incident_id = body["auto_sos"]["incident_id"]

        detail = await self.client.get(f"/api/v1/incidents/{incident_id}", headers=self.headers)

        self.assertEqual(detail.status_code, 200, detail.text)
        # A report that cannot say whether a human or the system raised the
        # alarm is not forensic-grade, whatever else is in it.
        self.assertEqual(detail.json()["title"], "Automatic SOS")

    async def test_a_second_alert_is_deduplicated(self):
        # SRS §6.2 / TC-EMG-05. Every contact of a woman already in an
        # emergency must not be alerted twice for the same one.
        for _ in range(10):
            body = await self._heartbeat(100.0)
            if body["auto_sos"]["triggered"]:
                break
        self.assertTrue(body["auto_sos"]["triggered"])

        second = await self._heartbeat(100.0)

        self.assertFalse(second["auto_sos"]["triggered"])
        self.assertIn("less than", second["auto_sos"]["reason"])


if __name__ == "__main__":
    unittest.main()
