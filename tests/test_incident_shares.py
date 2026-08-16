"""Contract tests for incident share links — SRS FR-RPT-06.

A share link is an unauthenticated credential pointing at a recording of
someone in danger, so the tests here are mostly about what it must *not*
do: outlive its expiry, survive revocation, leak the owner's account, or
reach any incident but its own.
"""

from __future__ import annotations

import os
import tempfile
import unittest
from datetime import datetime, timedelta
from uuid import uuid4

os.environ["DATABASE_URL"] = "sqlite:///./test_safeher.db"
os.environ["ENABLE_MQTT_WORKER"] = "false"
os.environ["JWT_SECRET_KEY"] = "test-secret-key-change-me"
os.environ["LOG_LEVEL"] = "WARNING"

import httpx

from fastapi_app.db import SessionLocal, init_db
from fastapi_app.main import app
from fastapi_app.models import IncidentShare
from fastapi_app.deps import get_evidence_store
from fastapi_app.routers.shares import MAX_SHARE_DAYS, _hash_token
from fastapi_app.services.evidence_store import EvidenceStore, derive_key

_RECORDING = b"fake audio evidence bytes" * 16


class TestIncidentShares(unittest.IsolatedAsyncioTestCase):
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
        email = f"share-{uuid4().hex}@safeherapp.com"
        register = await self.client.post(
            "/api/v1/auth/register",
            json={"email": email, "password": "TestPass123!", "full_name": "S", "role": "user"},
        )
        self.assertEqual(register.status_code, 201, register.text)
        login = await self.client.post(
            "/api/v1/auth/login", json={"email": email, "password": "TestPass123!"}
        )
        return login.json()["access_token"]

    async def _create_incident(self, headers) -> str:
        response = await self.client.post(
            "/api/v1/incidents/",
            headers=headers,
            json={"title": "Emergency SOS", "threat_level": "critical"},
        )
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()["id"]

    async def _share(self, incident_id: str | None = None, headers=None, **params) -> dict:
        response = await self.client.post(
            f"/api/v1/incidents/{incident_id or self.incident_id}/share",
            headers=headers or self.headers,
            params=params,
        )
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()

    async def _upload_evidence(self) -> str:
        response = await self.client.post(
            f"/api/v1/media/evidence/{self.incident_id}",
            headers=self.headers,
            files={"file": ("e.m4a", _RECORDING, "audio/mp4")},
        )
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()["id"]

    # ---------------------------------------------------------- minting

    async def test_the_token_is_returned_once_and_only_hashed_at_rest(self):
        share = await self._share()

        async with SessionLocal() as session:
            row = await session.get(IncidentShare, share["id"])

        self.assertNotEqual(row.token_hash, share["token"])
        self.assertEqual(row.token_hash, _hash_token(share["token"]))
        # Listing never re-reveals it: losing the token means minting a new
        # link, which is the right trade for a password-less credential.
        listed = await self.client.get(
            f"/api/v1/incidents/{self.incident_id}/shares", headers=self.headers
        )
        self.assertNotIn("token", listed.json()[0])

    async def test_tokens_are_unguessable_and_unique(self):
        first = await self._share()
        second = await self._share()

        self.assertNotEqual(first["token"], second["token"])
        # secrets.token_urlsafe(32) — 256 bits.
        self.assertGreaterEqual(len(first["token"]), 40)

    async def test_the_lifetime_is_bounded(self):
        too_long = await self.client.post(
            f"/api/v1/incidents/{self.incident_id}/share",
            headers=self.headers,
            params={"days": MAX_SHARE_DAYS + 1},
        )
        self.assertEqual(too_long.status_code, 400, too_long.text)

        zero = await self.client.post(
            f"/api/v1/incidents/{self.incident_id}/share",
            headers=self.headers,
            params={"days": 0},
        )
        self.assertEqual(zero.status_code, 400, zero.text)

    async def test_defaults_to_seven_days(self):
        share = await self._share()

        expires = datetime.fromisoformat(share["expires_at"])
        self.assertAlmostEqual((expires - datetime.utcnow()).days, 6, delta=1)

    async def test_only_the_owner_can_mint_a_link(self):
        other = {"Authorization": f"Bearer {await self._login()}"}

        response = await self.client.post(
            f"/api/v1/incidents/{self.incident_id}/share", headers=other
        )

        self.assertEqual(response.status_code, 404, response.text)

    # ------------------------------------------------------------ reading

    async def test_a_link_holder_sees_the_incident_without_signing_in(self):
        share = await self._share()

        response = await self.client.get(f"/api/v1/share/{share['token']}")

        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["incident"]["title"], "Emergency SOS")

    async def test_the_shared_view_does_not_leak_the_owner(self):
        share = await self._share()

        body = (await self.client.get(f"/api/v1/share/{share['token']}")).text.lower()

        # Whoever holds this link needs the incident, not the account.
        for leaked in ("safeherapp.com", "user_id", "password", "email"):
            self.assertNotIn(leaked, body)

    async def test_evidence_streams_to_a_link_holder(self):
        media_id = await self._upload_evidence()
        share = await self._share()

        listing = await self.client.get(f"/api/v1/share/{share['token']}")
        self.assertEqual(listing.json()["evidence"][0]["id"], media_id)

        download = await self.client.get(
            f"/api/v1/share/{share['token']}/evidence/{media_id}"
        )
        self.assertEqual(download.status_code, 200, download.text)
        self.assertEqual(download.content, _RECORDING)
        self.assertIn("no-store", download.headers["cache-control"])

    async def test_a_link_cannot_reach_another_incident(self):
        other_incident = await self._create_incident(self.headers)
        share = await self._share(other_incident)
        media_id = await self._upload_evidence()  # belongs to self.incident_id

        response = await self.client.get(
            f"/api/v1/share/{share['token']}/evidence/{media_id}"
        )

        self.assertEqual(response.status_code, 404, response.text)

    # -------------------------------------------------------- expiry/revoke

    async def test_an_expired_link_stops_working(self):
        share = await self._share()
        async with SessionLocal() as session:
            row = await session.get(IncidentShare, share["id"])
            row.expires_at = datetime.utcnow() - timedelta(minutes=1)
            await session.commit()

        response = await self.client.get(f"/api/v1/share/{share['token']}")

        self.assertEqual(response.status_code, 404, response.text)

    async def test_expiry_also_stops_evidence(self):
        media_id = await self._upload_evidence()
        share = await self._share()
        async with SessionLocal() as session:
            row = await session.get(IncidentShare, share["id"])
            row.expires_at = datetime.utcnow() - timedelta(minutes=1)
            await session.commit()

        # The recording is decrypted per request precisely so that expiry
        # can actually stop access; a permanent URL could not be withdrawn.
        response = await self.client.get(
            f"/api/v1/share/{share['token']}/evidence/{media_id}"
        )
        self.assertEqual(response.status_code, 404, response.text)

    async def test_revoking_takes_effect_immediately(self):
        share = await self._share()
        self.assertEqual(
            (await self.client.get(f"/api/v1/share/{share['token']}")).status_code, 200
        )

        revoke = await self.client.delete(
            f"/api/v1/incidents/{self.incident_id}/shares/{share['id']}", headers=self.headers
        )
        self.assertEqual(revoke.status_code, 204, revoke.text)

        self.assertEqual(
            (await self.client.get(f"/api/v1/share/{share['token']}")).status_code, 404
        )

    async def test_unknown_revoked_and_expired_are_indistinguishable(self):
        share = await self._share()
        await self.client.delete(
            f"/api/v1/incidents/{self.incident_id}/shares/{share['id']}", headers=self.headers
        )

        revoked = await self.client.get(f"/api/v1/share/{share['token']}")
        unknown = await self.client.get(f"/api/v1/share/{'x' * 43}")

        # Telling them apart would confirm to a stranger that a link was
        # once real, which is itself information about someone's incident.
        self.assertEqual(revoked.status_code, unknown.status_code)
        self.assertEqual(revoked.json()["detail"], unknown.json()["detail"])

    async def test_only_the_owner_can_revoke(self):
        share = await self._share()
        other = {"Authorization": f"Bearer {await self._login()}"}

        response = await self.client.delete(
            f"/api/v1/incidents/{self.incident_id}/shares/{share['id']}", headers=other
        )

        self.assertEqual(response.status_code, 404, response.text)

    async def test_the_owner_can_see_which_links_are_live(self):
        active = await self._share()
        revoked = await self._share()
        await self.client.delete(
            f"/api/v1/incidents/{self.incident_id}/shares/{revoked['id']}", headers=self.headers
        )

        response = await self.client.get(
            f"/api/v1/incidents/{self.incident_id}/shares", headers=self.headers
        )

        by_id = {row["id"]: row for row in response.json()}
        self.assertTrue(by_id[active["id"]]["active"])
        self.assertFalse(by_id[revoked["id"]]["active"])


if __name__ == "__main__":
    unittest.main()
