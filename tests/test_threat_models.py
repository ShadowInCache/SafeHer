"""The three-model pipeline contract — XGBoost, CNN+LSTM, YOLOv8.

No model is trained yet. What these tests protect is the contract around
them, and in particular the one property that fails silently and dangerously:
a sensor that did not report must never be scored as a sensor that looked
and saw calm.
"""

from __future__ import annotations

import os
import unittest
from uuid import uuid4

os.environ["DATABASE_URL"] = "sqlite:///./test_safeher.db"
os.environ["ENABLE_MQTT_WORKER"] = "false"
os.environ["JWT_SECRET_KEY"] = "test-secret-key-change-me"
os.environ["LOG_LEVEL"] = "WARNING"

import httpx

from fastapi_app.db import init_db
from fastapi_app.main import app
from fastapi_app.services import threat_fusion as tf
from fastapi_app.services import threat_models as tm


class TestPartialSensorCoverage(unittest.TestCase):
    """The reason `fuse_available` exists rather than a plain `fuse`."""

    def test_a_missing_modality_is_excluded_not_zeroed(self):
        # Zero-filling is the dangerous reading: it lets a switched-off camera
        # quietly hold the score down. "Did not look" and "looked and saw
        # nothing" have to produce different numbers.
        renormalised = tf.fuse(tf.ThreatSignals(glove=1.0, audio=1.0))
        zero_filled = tf.fuse(tf.ThreatSignals(glove=1.0, audio=1.0, weapon=0.0))

        self.assertAlmostEqual(renormalised, 1.0)
        self.assertLess(zero_filled, renormalised)

    def test_the_glove_alone_can_still_raise_the_alarm(self):
        # The glasses are the likelier of the two to be off, and the glove is
        # the only detector that exists today. Renormalisation is what keeps a
        # maximal glove reading at the top of the scale rather than at its
        # 0.25 weight, which could never reach any threshold.
        self.assertAlmostEqual(tf.fuse(tf.ThreatSignals(glove=1.0)), 1.0)

    def test_weights_stay_proportional_between_present_modalities(self):
        # audio outweighs glove (0.35 vs 0.25), so with the camera absent a
        # maximal audio reading must score above a maximal glove one. Asserted
        # as a direction rather than a ratio: the solo-signal floor deliberately
        # lifts a lone strong signal, so exact proportions do not survive it.
        glove_only = tf.fuse(tf.ThreatSignals(glove=1.0, audio=0.0))
        audio_only = tf.fuse(tf.ThreatSignals(glove=0.0, audio=1.0))

        self.assertGreater(audio_only, glove_only)

    def test_no_modality_at_all_is_none_not_zero(self):
        # "Nothing reported" and "everything reported calm" must not be the
        # same value: one is an outage, the other is safety.
        self.assertIsNone(tf.fuse(tf.ThreatSignals()))

    def test_a_real_zero_is_still_honoured(self):
        # A sensor that reports 0.0 genuinely observed calm, and that must
        # not be confused with absence.
        self.assertEqual(tf.fuse(tf.ThreatSignals(glove=0.0)), 0.0)


class TestHeartRateIsNotAThreatSignal(unittest.TestCase):
    """A racing pulse is evidence of running for a bus.

    It used to add +0.05 to the fused score. Under the three-signal
    architecture it is supporting context: recorded on the incident, shown on
    the dashboard, and incapable of moving the number that summons people.
    """

    def test_the_booster_is_gone(self):
        self.assertFalse(hasattr(tf, "heart_rate_boost"))
        self.assertFalse(hasattr(tf, "HEART_RATE_BOOST"))

    def test_it_has_a_home_in_supporting_context(self):
        # Removed from the score, not thrown away -- the SRS §9.1 glove BOM
        # has no pulse sensor at all, so this is where one would report.
        context = tf.SupportingContext(heart_rate_bpm=150)
        self.assertEqual(context.heart_rate_bpm, 150)

    def test_it_is_not_a_field_a_score_can_read(self):
        self.assertNotIn("heart_rate_bpm", tf.PRIMARY_SIGNAL_NAMES)


class TestRegistry(unittest.TestCase):
    def test_every_fusion_modality_has_a_declared_model(self):
        self.assertEqual(
            {spec.modality for spec in tm.MODELS}, {"motion", "audio", "vision"}
        )

    def test_the_algorithms_are_the_ones_chosen_for_the_product(self):
        by_modality = tm.MODELS_BY_MODALITY
        self.assertEqual(by_modality["motion"].algorithm, "XGBoost")
        self.assertEqual(by_modality["audio"].algorithm, "CNN + LSTM")
        self.assertEqual(by_modality["vision"].algorithm, "YOLOv8")

    def test_nothing_claims_to_be_trained(self):
        # This test is expected to be changed -- deliberately. Marking a
        # model ready is then a visible decision in a diff rather than a
        # default that drifted.
        self.assertFalse(tm.registry_report()["any_ready"])

    def test_the_report_admits_where_scores_come_from(self):
        # With no trained model, every score the backend sees came from a
        # caller. Saying so is the difference between a pipeline that is
        # ready and one that is running.
        self.assertTrue(tm.registry_report()["scores_are_caller_supplied"])

    def test_reporting_modalities_lists_only_what_reported(self):
        scores = tm.ModalityScores(motion=0.5, vision=0.2)

        self.assertEqual(scores.reporting_modalities, ["motion", "vision"])
        self.assertTrue(scores.has_any)

    def test_an_empty_read_reports_nothing(self):
        self.assertFalse(tm.ModalityScores().has_any)


class TestAnalyzeEndpoint(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://testserver"
        )
        email = f"analyze-{uuid4().hex}@safeherapp.com"
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

    async def _analyze(self, **payload) -> httpx.Response:
        return await self.client.post(
            "/api/v1/alerts/analyze", headers=self.headers, json=payload
        )

    async def test_a_read_with_no_modality_is_refused(self):
        # Scoring it would mean inventing a number for a moment nothing
        # observed -- and that number would then be smoothed into every
        # reading after it.
        response = await self._analyze(heart_rate_bpm=140)

        self.assertEqual(response.status_code, 422, response.text)
        self.assertIn("No modality reported", response.text)

    async def test_it_reports_which_sensors_the_verdict_rests_on(self):
        response = await self._analyze(motion_score=0.3, audio_score=0.2)

        self.assertEqual(response.status_code, 202, response.text)
        self.assertEqual(response.json()["modalities_used"], ["motion", "audio"])

    async def test_a_calm_read_raises_nothing(self):
        response = await self._analyze(motion_score=0.1, audio_score=0.1, vision_score=0.1)

        self.assertFalse(response.json()["auto_sos"]["triggered"])

    async def test_a_sustained_three_sensor_threat_dispatches(self):
        for _ in range(10):
            body = (await self._analyze(
                motion_score=1.0, audio_score=1.0, vision_score=1.0
            )).json()
            if body["auto_sos"]["triggered"]:
                break

        self.assertTrue(body["auto_sos"]["triggered"], body)

    async def test_the_glasses_being_off_does_not_disable_the_alarm(self):
        # The whole point of renormalisation, end to end: glove-only, no
        # camera, no microphone, and the alarm still reaches the threshold.
        for _ in range(10):
            body = (await self._analyze(motion_score=1.0)).json()
            if body["auto_sos"]["triggered"]:
                break

        self.assertEqual(body["modalities_used"], ["motion"])
        self.assertTrue(body["auto_sos"]["triggered"], body)

    async def test_the_registry_is_reachable_and_honest(self):
        response = await self.client.get("/api/v1/alerts/models", headers=self.headers)

        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        self.assertFalse(body["pipeline_live"])
        self.assertEqual(len(body["models"]), 3)

    async def test_the_registry_needs_authentication(self):
        response = await self.client.get("/api/v1/alerts/models")

        self.assertIn(response.status_code, (401, 403))


if __name__ == "__main__":
    unittest.main()
