"""GDPR Article 15 — the export the app promised and did not have.

The Profile screen has shipped a "Download My Data" button since the data and
privacy section was built. Tapping it opened a sheet that summarised what an
export *would* contain and admitted, in small grey text, that "a full export
requires a live backend export endpoint, which isn't wired up in this build
yet". That is an honest placeholder and it is not a feature: erasure
(Article 17) was implemented, access (Article 15) was not.

These tests pin the two properties that matter more than the field list.
An export must contain the user's own data and *only* the user's own data —
it is the one endpoint whose entire job is to hand over everything at once,
so a scoping mistake here leaks more than anywhere else in the system. And it
must not carry credentials: an export is a document that ends up in a
Downloads folder, a chat thread, an email to a lawyer.
"""

from __future__ import annotations

import json
import os
import unittest
from uuid import uuid4

os.environ.setdefault("DATABASE_URL", "sqlite:///./test_safeher.db")
os.environ.setdefault("ENABLE_MQTT_WORKER", "false")
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-key-change-me")

import httpx

from fastapi_app.db import init_db
from fastapi_app.main import app


class TestDataExport(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://testserver",
        )
        self.email = f"export-{uuid4().hex}@safeherapp.com"
        self.headers = {"Authorization": f"Bearer {await self._login(self.email)}"}

    async def asyncTearDown(self):
        await self.client.aclose()

    async def _login(self, email: str) -> str:
        register = await self.client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "password": "TestPass123!",
                "full_name": "Priya Patel",
                "role": "user",
            },
        )
        self.assertEqual(register.status_code, 201, register.text)
        login = await self.client.post(
            "/api/v1/auth/login", json={"email": email, "password": "TestPass123!"}
        )
        self.assertEqual(login.status_code, 200, login.text)
        return login.json()["access_token"]

    async def test_export_requires_authentication(self):
        response = await self.client.get("/api/v1/users/me/export")
        self.assertIn(response.status_code, (401, 403), response.text)

    async def test_export_contains_the_users_own_records(self):
        await self.client.post(
            "/api/v1/users/me/emergency-contacts",
            headers=self.headers,
            json={
                "name": "Akshatha",
                "phone": "+919000000001",
                "relationship": "Friend",
                "priority": 1,
            },
        )
        await self.client.post(
            "/api/v1/alerts/emergency",
            headers=self.headers,
            json={
                "severity": "critical",
                "summary": "SOS",
                "location": {"latitude": 12.85, "longitude": 77.68},
            },
        )

        response = await self.client.get("/api/v1/users/me/export", headers=self.headers)
        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()

        self.assertEqual(body["account"]["email"], self.email)
        self.assertEqual(len(body["emergency_contacts"]), 1)
        self.assertEqual(body["emergency_contacts"][0]["name"], "Akshatha")
        self.assertGreaterEqual(len(body["incidents"]), 1)
        self.assertGreaterEqual(len(body["locations"]), 1)
        self.assertEqual(body["locations"][0]["latitude"], 12.85)

    async def test_export_holds_no_other_accounts_data(self):
        """The scoping test. This endpoint returns everything at once, so a
        missing `where user_id =` leaks more here than anywhere else."""
        other_email = f"other-{uuid4().hex}@safeherapp.com"
        other_headers = {"Authorization": f"Bearer {await self._login(other_email)}"}
        await self.client.post(
            "/api/v1/users/me/emergency-contacts",
            headers=other_headers,
            json={
                "name": "Someone Elses Sister",
                "phone": "+919111111111",
                "relationship": "Sister",
                "priority": 1,
            },
        )

        response = await self.client.get("/api/v1/users/me/export", headers=self.headers)
        self.assertEqual(response.status_code, 200, response.text)

        serialised = json.dumps(response.json())
        self.assertNotIn("Someone Elses Sister", serialised)
        self.assertNotIn("+919111111111", serialised)
        self.assertNotIn(other_email, serialised)

    async def test_export_carries_no_credentials(self):
        """An export lands in a Downloads folder. It carries her data, not the
        secrets that protect it."""
        response = await self.client.get("/api/v1/users/me/export", headers=self.headers)
        self.assertEqual(response.status_code, 200, response.text)

        serialised = json.dumps(response.json()).lower()
        for forbidden in (
            "password_hash",
            "verification_code_hash",
            "token_hash",
            "auth_secret",
            "pin_hash",
            "tokens_valid_from",
        ):
            self.assertNotIn(forbidden, serialised, f"{forbidden} is in the export")

    async def test_evidence_is_referenced_and_never_inlined(self):
        """Recordings are linked, not embedded.

        They are encrypted at rest and streamed per request precisely so a
        recording of an assault is not sitting in plaintext somewhere less
        careful. Base64-ing one into the export would undo that.
        """
        response = await self.client.get("/api/v1/users/me/export", headers=self.headers)
        body = response.json()

        self.assertIn("evidence", body)
        for item in body["evidence"]:
            self.assertNotIn("bytes", item)
            self.assertNotIn("content", item)
            self.assertTrue(item["download"].startswith("/api/v1/media/evidence/"))


if __name__ == "__main__":
    unittest.main()
