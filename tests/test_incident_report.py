"""Contract tests for the PDF report and the evidence follow-up.

Covers SRS FR-RPT-03 (forensic PDF with a chain-of-custody hash) and the
half of FR-EMG-05 that cannot travel in the alert itself — the evidence URL,
which does not exist until the recording is finished and uploaded.
"""

from __future__ import annotations

import hashlib
import os
import re
import tempfile
import unittest
from uuid import uuid4

os.environ["DATABASE_URL"] = "sqlite:///./test_safeher.db"
os.environ["ENABLE_MQTT_WORKER"] = "false"
os.environ["JWT_SECRET_KEY"] = "test-secret-key-change-me"
os.environ["LOG_LEVEL"] = "WARNING"

import httpx

from fastapi_app.db import init_db
from fastapi_app.deps import get_evidence_store
from fastapi_app.main import app
from fastapi_app.services.evidence_store import EvidenceStore, derive_key
from fastapi_app.services.incident_pdf import build_incident_pdf, sha256_hex

_RECORDING = b"audio evidence for the report" * 12


def pdf_text(pdf: bytes) -> str:
    """Returns the readable text of a PDF.

    fpdf2 Flate-compresses its content streams, so searching the raw bytes
    finds nothing -- an easy way to write an assertion that passes for the
    wrong reason, or fails for one. The first draft of these tests did
    exactly that.
    """
    import zlib

    chunks = []
    for match in re.finditer(rb"stream\r?\n(.*?)endstream", pdf, re.S):
        try:
            chunks.append(zlib.decompress(match.group(1)).decode("latin-1"))
        except zlib.error:
            chunks.append(match.group(1).decode("latin-1"))
    return "\n".join(chunks)



class TestPdfBuilder(unittest.TestCase):
    """The renderer is pure, so it gets plain unit tests."""

    def _build(self, **overrides) -> bytes:
        from datetime import datetime

        kwargs = {
            "incident_title": "Emergency SOS",
            "incident_description": "Triggered manually.",
            "threat_level": "critical",
            "occurred_at": datetime(2026, 8, 15, 14, 5),
            "reported_by": "Priya Patel",
            "latitude": 17.3850,
            "longitude": 78.4867,
            "evidence": [("media-1", "audio/mp4", _RECORDING)],
        }
        kwargs.update(overrides)
        return build_incident_pdf(**kwargs)

    def test_produces_a_real_pdf(self):
        pdf = self._build()

        self.assertTrue(pdf.startswith(b"%PDF-"))
        self.assertGreater(len(pdf), 1000)

    def test_carries_the_evidence_hash(self):
        pdf = self._build()
        digest = sha256_hex(_RECORDING)

        # Grouped in eights on the page so a reader can compare it by hand;
        # a hash nobody can read is a hash nobody checks.
        self.assertIn(digest[:8], pdf_text(pdf))

    def test_the_hash_tracks_the_bytes(self):
        one = self._build()
        two = self._build(evidence=[("media-1", "audio/mp4", _RECORDING + b"x")])

        self.assertNotEqual(one, two)

    def test_says_so_when_there_is_no_location(self):
        pdf = pdf_text(self._build(latitude=None, longitude=None))

        # "No fix was available" and "nobody filled this in" are different
        # facts about an incident.
        self.assertIn("No location was captured", pdf)

    def test_says_so_when_there_is_no_evidence(self):
        pdf = pdf_text(self._build(evidence=[]))

        self.assertIn("No evidence was captured", pdf)

    def test_does_not_overstate_what_the_hash_proves(self):
        pdf = pdf_text(self._build())

        # Overstating this is worse than omitting it: a reader who believes
        # the report is signed will treat it as proof of authorship.
        self.assertIn("not a signature", pdf)

    def test_the_recording_itself_is_not_embedded(self):
        pdf = self._build()

        # A report gets forwarded to people who should read the summary, not
        # listen to the audio.
        self.assertNotIn(_RECORDING, pdf)


class TestReportApi(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self._dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._dir.cleanup)
        self.store = EvidenceStore(directory=self._dir.name, key=derive_key("test-key"))
        app.dependency_overrides[get_evidence_store] = lambda: self.store

        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://testserver"
        )
        self.headers = {"Authorization": f"Bearer {await self._login()}"}
        self.incident_id = await self._create_incident()

    async def asyncTearDown(self):
        app.dependency_overrides.pop(get_evidence_store, None)
        await self.client.aclose()

    async def _login(self) -> str:
        email = f"report-{uuid4().hex}@safeherapp.com"
        await self.client.post(
            "/api/v1/auth/register",
            json={"email": email, "password": "TestPass123!", "full_name": "Priya", "role": "user"},
        )
        login = await self.client.post(
            "/api/v1/auth/login", json={"email": email, "password": "TestPass123!"}
        )
        return login.json()["access_token"]

    async def _create_incident(self) -> str:
        response = await self.client.post(
            "/api/v1/incidents/",
            headers=self.headers,
            json={"title": "Emergency SOS", "threat_level": "critical"},
        )
        return response.json()["id"]

    async def _upload(self, *, notify: bool = False):
        return await self.client.post(
            f"/api/v1/media/evidence/{self.incident_id}",
            headers=self.headers,
            params={"notify_contacts": notify} if notify else None,
            files={"file": ("e.m4a", _RECORDING, "audio/mp4")},
        )

    async def test_exports_a_pdf(self):
        await self._upload()

        response = await self.client.get(
            f"/api/v1/incidents/{self.incident_id}/report.pdf", headers=self.headers
        )

        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.headers["content-type"], "application/pdf")
        self.assertTrue(response.content.startswith(b"%PDF-"))
        self.assertIn("attachment", response.headers["content-disposition"])

    async def test_the_exported_hash_matches_the_stored_recording(self):
        await self._upload()

        response = await self.client.get(
            f"/api/v1/incidents/{self.incident_id}/report.pdf", headers=self.headers
        )

        # The whole point: someone handed the recording separately can
        # re-hash it and compare against the report.
        digest = hashlib.sha256(_RECORDING).hexdigest()
        self.assertIn(digest[:8], pdf_text(response.content))

    async def test_a_report_without_evidence_still_exports(self):
        response = await self.client.get(
            f"/api/v1/incidents/{self.incident_id}/report.pdf", headers=self.headers
        )

        self.assertEqual(response.status_code, 200, response.text)

    async def test_another_user_cannot_export_your_report(self):
        other = {"Authorization": f"Bearer {await self._login()}"}

        response = await self.client.get(
            f"/api/v1/incidents/{self.incident_id}/report.pdf", headers=other
        )

        self.assertEqual(response.status_code, 404, response.text)

    async def test_the_report_requires_authentication(self):
        response = await self.client.get(f"/api/v1/incidents/{self.incident_id}/report.pdf")

        self.assertIn(response.status_code, (401, 403), response.text)

    # ------------------------------------------------------------ follow-up

    async def test_upload_does_not_notify_unless_asked(self):
        response = await self._upload()

        self.assertEqual(response.status_code, 201, response.text)
        self.assertEqual(response.json()["followup"]["contacts_notified"], 0)

    async def test_a_follow_up_never_costs_the_recording(self):
        # Email is unconfigured in tests, so the follow-up cannot send. The
        # upload must still succeed: losing a stored recording because a
        # second email bounced would be the wrong trade entirely.
        await self.client.post(
            "/api/v1/users/me/emergency-contacts",
            headers=self.headers,
            json={
                "name": "Anika",
                "phone": "+911111111111",
                "email": "anika@example.com",
                "relationship": "Sister",
                "priority": 1,
            },
        )

        response = await self._upload(notify=True)

        self.assertEqual(response.status_code, 201, response.text)
        self.assertIn("id", response.json())


if __name__ == "__main__":
    unittest.main()
