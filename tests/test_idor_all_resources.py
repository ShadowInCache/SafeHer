"""IDOR / BOLA sweep across every user-owned resource.

Companion to `test_cross_account_isolation.py`, which covers contacts and
profile. This one drives two real accounts against incidents, evidence,
journeys (GPS), devices, notifications, shares, SOS dispatch and AI-generated
summaries, and asserts that account B is refused on every object owned by A.

The rule under test is the same everywhere: an id supplied by the client is
an *assertion*, never a permission. Every route that accepts one has to
re-derive ownership from the token.
"""

import unittest
from uuid import uuid4

import httpx

from fastapi_app.db import init_db
from fastapi_app.main import app

DENIED = (401, 403, 404)


class TestIdorAcrossResources(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://testserver"
        )
        self.a = {"Authorization": f"Bearer {await self._login(f'idor-a-{uuid4().hex}@safeherapp.com')}"}
        self.b = {"Authorization": f"Bearer {await self._login(f'idor-b-{uuid4().hex}@safeherapp.com')}"}

    async def asyncTearDown(self):
        await self.client.aclose()

    async def _login(self, email: str) -> str:
        await self.client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "password": "TestPass123!",
                "full_name": "IDOR Test",
                "phone": "+15550100000",
            },
        )
        login = await self.client.post(
            "/api/v1/auth/login", json={"email": email, "password": "TestPass123!"}
        )
        self.assertEqual(login.status_code, 200, login.text)
        return login.json()["access_token"]

    async def _incident(self, headers) -> str:
        """An incident owned by whoever `headers` belongs to."""
        response = await self.client.post(
            "/api/v1/incidents/",
            json={"title": "A's incident", "description": "owned by A", "threat_level": "high"},
            headers=headers,
        )
        self.assertIn(response.status_code, (200, 201), response.text)
        return response.json()["id"]

    # ------------------------------------------------------------- incidents

    async def test_b_cannot_read_a_incident(self):
        incident_id = await self._incident(self.a)
        response = await self.client.get(f"/api/v1/incidents/{incident_id}", headers=self.b)
        self.assertIn(response.status_code, DENIED, response.text)

    async def test_b_cannot_download_a_incident_report(self):
        incident_id = await self._incident(self.a)
        response = await self.client.get(
            f"/api/v1/incidents/{incident_id}/report.pdf", headers=self.b
        )
        self.assertIn(response.status_code, DENIED, response.text)

    async def test_b_cannot_generate_ai_summary_on_a_incident(self):
        incident_id = await self._incident(self.a)
        response = await self.client.post(
            f"/api/v1/incidents/{incident_id}/summary", headers=self.b
        )
        self.assertIn(response.status_code, DENIED, response.text)

    async def test_incident_listing_is_per_account(self):
        await self._incident(self.a)
        listing = await self.client.get("/api/v1/incidents/", headers=self.b)
        self.assertEqual(listing.status_code, 200, listing.text)
        payload = listing.json()
        rows = payload if isinstance(payload, list) else payload.get("items", [])
        self.assertEqual(rows, [], "a fresh account must see no incidents")

    # -------------------------------------------------------------- evidence

    async def test_b_cannot_list_a_incident_evidence(self):
        incident_id = await self._incident(self.a)
        response = await self.client.get(
            f"/api/v1/media/evidence/incident/{incident_id}/list", headers=self.b
        )
        self.assertIn(response.status_code, DENIED, response.text)

    async def test_b_cannot_attach_evidence_to_a_incident(self):
        incident_id = await self._incident(self.a)
        response = await self.client.post(
            f"/api/v1/media/evidence/{incident_id}",
            files={"file": ("eve.txt", b"planted", "text/plain")},
            headers=self.b,
        )
        self.assertIn(response.status_code, DENIED + (400, 422), response.text)

    # ------------------------------------------------------- journeys / GPS

    async def _journey(self, headers) -> str:
        response = await self.client.post(
            "/api/v1/journeys",
            json={
                "destination_label": "Home",
                "destination_lat": 12.9,
                "destination_lng": 77.6,
                "expected_duration_minutes": 30,
            },
            headers=headers,
        )
        self.assertIn(response.status_code, (200, 201), response.text)
        return response.json()["id"]

    async def test_b_cannot_read_a_journey_locations(self):
        journey_id = await self._journey(self.a)
        response = await self.client.get(
            f"/api/v1/journeys/{journey_id}/locations", headers=self.b
        )
        self.assertIn(response.status_code, DENIED, response.text)

    async def test_b_cannot_post_locations_into_a_journey(self):
        journey_id = await self._journey(self.a)
        response = await self.client.post(
            f"/api/v1/journeys/{journey_id}/locations",
            json={"latitude": 0.0, "longitude": 0.0},
            headers=self.b,
        )
        self.assertIn(response.status_code, DENIED + (422,), response.text)

    async def test_b_cannot_cancel_or_escalate_a_journey(self):
        journey_id = await self._journey(self.a)
        for action in ("cancel", "escalate", "arrive", "check-in"):
            response = await self.client.post(
                f"/api/v1/journeys/{journey_id}/{action}", headers=self.b
            )
            self.assertIn(
                response.status_code,
                DENIED + (422,),
                f"{action} must not be triggerable on another account's journey: {response.text}",
            )

    # --------------------------------------------------------------- devices

    async def test_b_cannot_delete_a_device(self):
        registered = await self.client.post(
            "/api/v1/devices/register",
            json={"device_name": "A Glove", "device_type": "smart_glove"},
            headers=self.a,
        )
        self.assertIn(registered.status_code, (200, 201), registered.text)
        device_id = registered.json()["id"]

        response = await self.client.delete(f"/api/v1/devices/{device_id}", headers=self.b)
        self.assertIn(response.status_code, DENIED, response.text)

        still_there = await self.client.get("/api/v1/devices/me", headers=self.a)
        ids = [d["id"] for d in still_there.json()]
        self.assertIn(device_id, ids, "A's device must survive B's delete")

    async def test_device_listing_is_per_account(self):
        await self.client.post(
            "/api/v1/devices/register",
            json={"device_name": "A Glove", "device_type": "smart_glove"},
            headers=self.a,
        )
        listing = await self.client.get("/api/v1/devices/me", headers=self.b)
        self.assertEqual(listing.status_code, 200, listing.text)
        self.assertEqual(listing.json(), [], "a fresh account owns no devices")

    # ------------------------------------------------------------------ SOS

    async def test_b_cannot_read_a_emergency_dispatch(self):
        incident_id = await self._incident(self.a)
        response = await self.client.get(
            f"/api/v1/alerts/emergency/{incident_id}/dispatch", headers=self.b
        )
        self.assertIn(response.status_code, DENIED, response.text)

    # ---------------------------------------------------------------- shares

    async def test_b_cannot_mint_a_share_link_for_a_incident(self):
        incident_id = await self._incident(self.a)
        response = await self.client.post(
            f"/api/v1/incidents/{incident_id}/share", json={}, headers=self.b
        )
        self.assertIn(response.status_code, DENIED + (422,), response.text)

    async def test_b_cannot_list_a_share_links(self):
        incident_id = await self._incident(self.a)
        response = await self.client.get(
            f"/api/v1/incidents/{incident_id}/shares", headers=self.b
        )
        self.assertIn(response.status_code, DENIED, response.text)

    # --------------------------------------------------------- notifications

    async def test_push_tokens_are_per_account(self):
        await self.client.post(
            "/api/v1/notifications/register-token",
            json={"token": f"tok-{uuid4().hex}", "platform": "android"},
            headers=self.a,
        )
        listing = await self.client.get("/api/v1/notifications/tokens", headers=self.b)
        self.assertEqual(listing.status_code, 200, listing.text)
        rows = listing.json()
        rows = rows if isinstance(rows, list) else rows.get("items", [])
        self.assertEqual(rows, [], "B must not see A's push tokens")

    # ------------------------------------------------------------- dashboard

    async def test_dashboard_is_per_account(self):
        await self._incident(self.a)
        summary = await self.client.get("/api/v1/dashboard/summary", headers=self.b)
        self.assertEqual(summary.status_code, 200, summary.text)
        # B has no incidents, so nothing in B's summary may be non-zero on a
        # count that A alone generated.
        body = summary.json()
        for key in ("total_incidents", "incident_count", "incidents"):
            if isinstance(body.get(key), int):
                self.assertEqual(body[key], 0, f"{key} leaked A's data into B's dashboard")


if __name__ == "__main__":
    unittest.main()
