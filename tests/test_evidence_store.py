"""Contract tests for emergency evidence — SRS FR-EMG-06 and FR-EMG-07.

Evidence here is a recording of an assault in progress. The properties worth
pinning are the ones that protect the person in it: it is unreadable on
disk, it cannot be fetched by anyone but its owner, and a file that has been
tampered with is refused rather than served.
"""

from __future__ import annotations

import os
import tempfile
import unittest
from uuid import uuid4

os.environ["DATABASE_URL"] = "sqlite:///./test_safeher.db"
os.environ["ENABLE_MQTT_WORKER"] = "false"
os.environ["JWT_SECRET_KEY"] = "test-secret-key-change-me"
os.environ["LOG_LEVEL"] = "WARNING"

import httpx

from fastapi_app.db import init_db
from fastapi_app.main import app
from fastapi_app.deps import get_evidence_store
from fastapi_app.services.evidence_store import (
    EvidenceStore,
    EvidenceStoreError,
    derive_key,
)

_RECORDING = b"RIFF....fake audio bytes for a test...." * 8


class TestEvidenceStoreUnit(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._dir.cleanup)
        self.store = EvidenceStore(directory=self._dir.name, key=derive_key("a-secret"))

    def test_round_trips(self):
        storage_id = self.store.write(_RECORDING)

        self.assertEqual(self.store.read(storage_id), _RECORDING)

    def test_nothing_readable_is_left_on_disk(self):
        self.store.write(_RECORDING)

        for name in os.listdir(self._dir.name):
            blob = open(os.path.join(self._dir.name, name), "rb").read()
            # The whole point of FR-EMG-07: a stolen backup yields ciphertext.
            self.assertNotIn(b"fake audio bytes", blob)
            self.assertNotEqual(blob, _RECORDING)

    def test_two_writes_of_identical_audio_differ_on_disk(self):
        first = self.store.write(_RECORDING)
        second = self.store.write(_RECORDING)

        blob_one = open(os.path.join(self._dir.name, f"{first}.enc"), "rb").read()
        blob_two = open(os.path.join(self._dir.name, f"{second}.enc"), "rb").read()

        # A fresh nonce per write. Identical ciphertext would leak that two
        # recordings are the same without decrypting either.
        self.assertNotEqual(blob_one, blob_two)

    def test_a_tampered_file_is_refused_not_returned(self):
        storage_id = self.store.write(_RECORDING)
        path = os.path.join(self._dir.name, f"{storage_id}.enc")
        blob = bytearray(open(path, "rb").read())
        blob[-1] ^= 0xFF
        open(path, "wb").write(bytes(blob))

        # AES-GCM authenticates. Evidence that may have been altered is not
        # evidence, so it is refused rather than handed back.
        with self.assertRaises(EvidenceStoreError):
            self.store.read(storage_id)

    def test_a_different_key_cannot_read_it(self):
        storage_id = self.store.write(_RECORDING)
        other = EvidenceStore(directory=self._dir.name, key=derive_key("a-different-secret"))

        with self.assertRaises(EvidenceStoreError):
            other.read(storage_id)

    def test_empty_recordings_are_rejected(self):
        with self.assertRaises(EvidenceStoreError):
            self.store.write(b"")

    def test_key_derivation_is_deterministic_and_secret_specific(self):
        self.assertEqual(derive_key("secret"), derive_key("secret"))
        self.assertNotEqual(derive_key("secret"), derive_key("other"))
        self.assertEqual(len(derive_key("secret")), 32)

    def test_an_explicit_key_overrides_the_derived_one(self):
        self.assertNotEqual(
            derive_key("secret"), derive_key("secret", explicit_key="managed-key")
        )

    def test_the_derived_key_is_not_the_signing_secret(self):
        # Shares a root with JWT_SECRET_KEY but must not equal it, or a leak
        # of one would be a leak of both.
        secret = "a-secret"
        self.assertNotEqual(derive_key(secret), secret.encode("utf-8"))

    def test_a_short_key_is_rejected(self):
        with self.assertRaises(EvidenceStoreError):
            EvidenceStore(directory=self._dir.name, key=b"too-short")


class TestEvidenceApi(unittest.IsolatedAsyncioTestCase):
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
        self.incident_id = await self._create_incident(self.headers)

    async def asyncTearDown(self):
        app.dependency_overrides.pop(get_evidence_store, None)
        await self.client.aclose()

    async def _login(self) -> str:
        email = f"evidence-{uuid4().hex}@safeherapp.com"
        register = await self.client.post(
            "/api/v1/auth/register",
            json={"email": email, "password": "TestPass123!", "full_name": "E", "role": "user"},
        )
        self.assertEqual(register.status_code, 201, register.text)
        login = await self.client.post(
            "/api/v1/auth/login", json={"email": email, "password": "TestPass123!"}
        )
        self.assertEqual(login.status_code, 200, login.text)
        return login.json()["access_token"]

    async def _create_incident(self, headers) -> str:
        response = await self.client.post(
            "/api/v1/incidents/", headers=headers, json={"title": "SOS", "threat_level": "high"}
        )
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()["id"]

    def _upload_body(self, *, content_type: str = "audio/mp4", data: bytes = _RECORDING):
        return {"file": ("evidence.m4a", data, content_type)}

    # ------------------------------------------------------------- uploading

    async def test_uploads_and_reads_back_identically(self):
        upload = await self.client.post(
            f"/api/v1/media/evidence/{self.incident_id}",
            headers=self.headers,
            files=self._upload_body(),
        )
        self.assertEqual(upload.status_code, 201, upload.text)
        media_id = upload.json()["id"]

        download = await self.client.get(
            f"/api/v1/media/evidence/{media_id}", headers=self.headers
        )
        self.assertEqual(download.status_code, 200, download.text)
        self.assertEqual(download.content, _RECORDING)

    async def test_no_public_url_is_returned(self):
        upload = await self.client.post(
            f"/api/v1/media/evidence/{self.incident_id}",
            headers=self.headers,
            files=self._upload_body(),
        )

        # A link that leaks must not be enough to play the recording, so the
        # response hands back an id, never a fetchable URL.
        body = upload.json()
        self.assertNotIn("url", body)
        self.assertFalse(any("http" in str(value) for value in body.values()))

    async def test_the_response_never_caches(self):
        upload = await self.client.post(
            f"/api/v1/media/evidence/{self.incident_id}",
            headers=self.headers,
            files=self._upload_body(),
        )
        download = await self.client.get(
            f"/api/v1/media/evidence/{upload.json()['id']}", headers=self.headers
        )

        self.assertIn("no-store", download.headers["cache-control"])
        self.assertIn("attachment", download.headers["content-disposition"])

    async def test_rejects_a_file_that_is_not_a_recording(self):
        response = await self.client.post(
            f"/api/v1/media/evidence/{self.incident_id}",
            headers=self.headers,
            files={"file": ("payload.zip", b"PK\\x03\\x04", "application/zip")},
        )

        self.assertEqual(response.status_code, 415, response.text)

    async def test_rejects_an_empty_recording(self):
        response = await self.client.post(
            f"/api/v1/media/evidence/{self.incident_id}",
            headers=self.headers,
            files=self._upload_body(data=b""),
        )

        self.assertEqual(response.status_code, 400, response.text)

    async def test_rejects_an_oversized_recording(self):
        from fastapi_app.config import get_settings

        oversize = b"x" * (get_settings().evidence_max_size_bytes + 1)
        response = await self.client.post(
            f"/api/v1/media/evidence/{self.incident_id}",
            headers=self.headers,
            files=self._upload_body(data=oversize),
        )

        self.assertEqual(response.status_code, 413, response.text)

    # -------------------------------------------------------------- ownership

    async def test_another_user_cannot_upload_to_your_incident(self):
        other = {"Authorization": f"Bearer {await self._login()}"}

        response = await self.client.post(
            f"/api/v1/media/evidence/{self.incident_id}",
            headers=other,
            files=self._upload_body(),
        )

        self.assertEqual(response.status_code, 404, response.text)

    async def test_another_user_cannot_download_your_evidence(self):
        upload = await self.client.post(
            f"/api/v1/media/evidence/{self.incident_id}",
            headers=self.headers,
            files=self._upload_body(),
        )
        media_id = upload.json()["id"]

        other = {"Authorization": f"Bearer {await self._login()}"}
        response = await self.client.get(
            f"/api/v1/media/evidence/{media_id}", headers=other
        )

        # 404 rather than 403: telling a stranger the id is real is itself
        # information about someone's incident.
        self.assertEqual(response.status_code, 404, response.text)

    async def test_evidence_requires_authentication(self):
        response = await self.client.get(f"/api/v1/media/evidence/{uuid4().hex}")
        self.assertIn(response.status_code, (401, 403), response.text)

    async def test_an_unknown_incident_is_not_confirmed_or_denied(self):
        response = await self.client.post(
            f"/api/v1/media/evidence/{uuid4().hex}",
            headers=self.headers,
            files=self._upload_body(),
        )

        self.assertEqual(response.status_code, 404, response.text)

    # ------------------------------------------------------------- listing

    async def test_lists_the_evidence_on_an_incident(self):
        for _ in range(2):
            await self.client.post(
                f"/api/v1/media/evidence/{self.incident_id}",
                headers=self.headers,
                files=self._upload_body(),
            )

        response = await self.client.get(
            f"/api/v1/media/evidence/incident/{self.incident_id}/list", headers=self.headers
        )

        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        self.assertEqual(len(body), 2)
        self.assertEqual(body[0]["media_type"], "audio/mp4")
        # Storage references stay server-side.
        self.assertNotIn("url", body[0])

    async def test_listing_someone_elses_incident_is_refused(self):
        other = {"Authorization": f"Bearer {await self._login()}"}

        response = await self.client.get(
            f"/api/v1/media/evidence/incident/{self.incident_id}/list", headers=other
        )

        self.assertEqual(response.status_code, 404, response.text)


if __name__ == "__main__":
    unittest.main()
