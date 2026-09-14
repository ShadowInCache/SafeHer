"""The web fallback for weapon detection, and the limits on it.

`POST /alerts/weapon-frame` is the only route that accepts a camera frame and
runs a model over it. Three things about it need holding in place, and none of
them is about the model's accuracy:

* it is authenticated, size-capped and rate-limited, because it is the most
  expensive thing an authenticated caller can ask the server to do;
* when no model is loaded it reports the modality **absent**, not zero — a zero
  claims the camera looked and saw calm, which caps the fused score below the
  alarm threshold and silently disables automatic dispatch;
* the expression classifier that rides along on the same frame lands in
  supporting context and can never reach the threat score.
"""

from __future__ import annotations

import io
import struct
import unittest
import zlib
from uuid import uuid4

import httpx

from fastapi_app.db import init_db
from fastapi_app.main import app
from fastapi_app.services import threat_models, weapon_detector


def _png(width: int = 8, height: int = 8) -> bytes:
    """A real, decodable PNG built by hand, so the test needs no image library."""

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    raw = b"".join(b"\x00" + b"\x80\x80\x80" * width for _ in range(height))
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )


class _Account(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://testserver"
        )
        email = f"wf-{uuid4().hex}@safeherapp.com"
        await self.client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "password": "TestPass123!",
                "full_name": "Frame Test",
                "phone": "+15550100000",
            },
        )
        login = await self.client.post(
            "/api/v1/auth/login", json={"email": email, "password": "TestPass123!"}
        )
        self.assertEqual(login.status_code, 200, login.text)
        self.auth = {"Authorization": f"Bearer {login.json()['access_token']}"}

    async def asyncTearDown(self):
        await self.client.aclose()

    async def _post(self, content: bytes, content_type: str = "image/png", **kwargs):
        return await self.client.post(
            "/api/v1/alerts/weapon-frame",
            files={"file": ("frame.png", io.BytesIO(content), content_type)},
            **kwargs,
        )


class TestWeaponFrameAccess(_Account):
    async def test_an_anonymous_caller_is_refused(self):
        response = await self._post(_png())
        self.assertIn(response.status_code, (401, 403), response.text)

    async def test_a_non_image_is_refused_before_any_inference(self):
        response = await self._post(
            b"not an image", content_type="application/pdf", headers=self.auth
        )
        self.assertEqual(response.status_code, 415, response.text)

    async def test_an_empty_frame_is_refused(self):
        response = await self._post(b"", headers=self.auth)
        self.assertEqual(response.status_code, 400, response.text)

    async def test_an_oversized_frame_is_refused(self):
        # The cap is enforced by reading with a limit rather than by trusting
        # Content-Length, which the caller controls.
        from fastapi_app.config import get_settings

        limit = get_settings().weapon_frame_max_size_bytes
        response = await self._post(b"\x89PNG\r\n\x1a\n" + b"\x00" * (limit + 1),
                                    headers=self.auth)
        self.assertEqual(response.status_code, 413, response.text)


class TestWeaponFrameHonesty(_Account):
    async def test_an_unloaded_model_reports_absent_and_not_zero(self):
        """The distinction the whole fusion design rests on."""
        original = weapon_detector.weapon_status
        weapon_detector.weapon_status = lambda: threat_models.ModelStatus.UNTRAINED
        try:
            response = await self._post(_png(), headers=self.auth)
        finally:
            weapon_detector.weapon_status = original

        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        self.assertFalse(body["available"])
        self.assertIsNone(
            body["weapon_confidence"],
            "a missing model must not report 0.0 -- that claims the camera "
            "looked and saw calm, which disables the automatic alarm",
        )
        self.assertIsNone(body["weapon_label"])

    async def test_a_loaded_model_returns_a_score_and_context(self):
        if weapon_detector.weapon_status() is not threat_models.ModelStatus.READY:
            self.skipTest("inference extras not installed in this environment")

        response = await self._post(_png(), headers=self.auth)
        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()

        self.assertTrue(body["available"])
        self.assertIsInstance(body["weapon_confidence"], float)
        self.assertGreaterEqual(body["weapon_confidence"], 0.0)
        self.assertLessEqual(body["weapon_confidence"], 1.0)
        # A flat grey square holds no weapon. If this ever fires, the
        # preprocessing contract has drifted.
        self.assertLess(body["weapon_confidence"], 0.5)

    async def test_emotion_is_returned_as_supporting_context_only(self):
        if weapon_detector.weapon_status() is not threat_models.ModelStatus.READY:
            self.skipTest("inference extras not installed in this environment")

        body = (await self._post(_png(), headers=self.auth)).json()

        # Present as context...
        self.assertIn("supporting_context", body)
        self.assertIn("emotion_label", body["supporting_context"])

        # ...and absent from every field that could become a score. The
        # architecture test enforces this inside `fuse()`; this enforces it at
        # the wire, so a future caller cannot pick expression up by accident.
        for forbidden in ("emotion_score", "emotion_confidence", "vision_score"):
            self.assertNotIn(
                forbidden,
                body,
                f"`{forbidden}` at the top level would make expression look "
                "like a fusion input",
            )


class TestFrameDecoding(unittest.TestCase):
    def test_undecodable_bytes_raise_rather_than_scoring(self):
        if weapon_detector.weapon_status() is not threat_models.ModelStatus.READY:
            self.skipTest("inference extras not installed in this environment")

        # Garbage must not quietly become "no weapon detected". That would be a
        # broken client reporting calm forever.
        with self.assertRaises(ValueError):
            weapon_detector.analyse_frame(b"\x89PNG\r\n\x1a\n" + b"garbage" * 64)


class TestPreprocessingContract(unittest.TestCase):
    """The input shapes this module assumes must be the ones the models declare.

    This exists because the emotion path shipped feeding 48x48 to a model that
    wants 96x96, with no ImageNet normalisation. It threw on every frame, the
    exception was swallowed, and the field came back null forever — and the
    endpoint test passed, because it only checked that the key was present.
    A null that means "silently broken" is indistinguishable from a null that
    means "no face in frame", which is exactly why this asserts the shape
    rather than the output.
    """

    def _declared_input(self, path):
        try:
            import onnxruntime
        except Exception:  # pragma: no cover - extras not installed
            self.skipTest("onnxruntime not installed in this environment")
        if not path.exists():
            self.skipTest(f"{path.name} not deployed in this environment")
        session = onnxruntime.InferenceSession(
            str(path), providers=["CPUExecutionProvider"]
        )
        return session.get_inputs()[0].shape

    def test_weapon_input_size_matches_the_model(self):
        shape = self._declared_input(weapon_detector.WEAPON_MODEL)
        self.assertEqual(
            [shape[2], shape[3]],
            [weapon_detector.INPUT_SIZE, weapon_detector.INPUT_SIZE],
        )

    def test_emotion_input_size_matches_the_model(self):
        shape = self._declared_input(weapon_detector.EMOTION_MODEL)
        self.assertEqual(
            [shape[2], shape[3]],
            [weapon_detector.EMOTION_INPUT_SIZE, weapon_detector.EMOTION_INPUT_SIZE],
            "the emotion model's declared input no longer matches the size "
            "this module feeds it -- inference will fail silently",
        )

    def test_a_frame_with_no_face_reports_no_expression(self):
        if weapon_detector.emotion_status() is not threat_models.ModelStatus.READY:
            self.skipTest("inference extras not installed in this environment")
        try:
            import cv2
            import numpy as np
        except Exception:  # pragma: no cover
            self.skipTest("opencv not installed in this environment")

        blank = np.full((240, 320, 3), 128, np.uint8)
        jpeg = cv2.imencode(".jpg", blank)[1].tobytes()

        verdict = weapon_detector.analyse_frame(jpeg)
        self.assertIsNone(
            verdict.emotion_label,
            "an expression reported for a frame containing no face is invented",
        )


if __name__ == "__main__":
    unittest.main()
