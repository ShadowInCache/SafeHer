"""Field tampering, privilege escalation, and token-forgery tests.

IDOR is about reaching another account's *objects*. This file covers the two
ways an attacker works on their own object instead: writing fields they are
not allowed to write (mass assignment / privilege escalation), and presenting
a token the server should refuse.

Everything here is written from the attacker's side -- craft the request,
then read the resulting state back through a normal authenticated route and
assert the protected field did not move.
"""

import base64
import json
import unittest
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import httpx
from jose import jwt

from fastapi_app.config import get_settings
from fastapi_app.db import init_db
from fastapi_app.main import app

DENIED = (401, 403)


class TestFieldTampering(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://testserver"
        )
        self.a_email = f"tamper-a-{uuid4().hex}@safeherapp.com"
        self.b_email = f"tamper-b-{uuid4().hex}@safeherapp.com"
        self.a = {"Authorization": f"Bearer {await self._login(self.a_email)}"}
        self.b = {"Authorization": f"Bearer {await self._login(self.b_email)}"}
        me = await self.client.get("/api/v1/users/me", headers=self.b)
        self.b_id = me.json()["id"]

    async def asyncTearDown(self):
        await self.client.aclose()

    async def _login(self, email: str) -> str:
        await self.client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "password": "TestPass123!",
                "full_name": "Tamper Test",
                "phone": "+15550100000",
            },
        )
        login = await self.client.post(
            "/api/v1/auth/login", json={"email": email, "password": "TestPass123!"}
        )
        self.assertEqual(login.status_code, 200, login.text)
        return login.json()["access_token"]

    # -------------------------------------------------- privilege escalation

    async def test_user_cannot_promote_themselves_to_admin(self):
        await self.client.patch(
            "/api/v1/users/me",
            json={"full_name": "A", "role": "admin"},
            headers=self.a,
        )

        me = await self.client.get("/api/v1/users/me", headers=self.a)
        self.assertNotEqual(
            me.json().get("role"), "admin", "role must not be settable by its owner"
        )

    async def test_user_cannot_flip_their_own_verified_status(self):
        # Asserted as "cannot change", not "is False": registration sets
        # is_verified itself when email verification is disabled (auth.py,
        # `user.is_verified = not required`), so an absolute assertion here
        # would fail against correct code and hide the real question, which
        # is whether a crafted body can move the field either way.
        before = (await self.client.get("/api/v1/users/me", headers=self.a)).json().get(
            "is_verified"
        )

        await self.client.patch(
            "/api/v1/users/me",
            json={"full_name": "A", "is_verified": not before},
            headers=self.a,
        )

        after = (await self.client.get("/api/v1/users/me", headers=self.a)).json().get(
            "is_verified"
        )
        self.assertEqual(
            after,
            before,
            "verified status is the server's to grant, not the client's to claim",
        )

    async def test_user_cannot_reassign_their_own_id(self):
        await self.client.patch(
            "/api/v1/users/me",
            json={"full_name": "A", "id": self.b_id},
            headers=self.a,
        )

        me = await self.client.get("/api/v1/users/me", headers=self.a)
        self.assertNotEqual(
            me.json()["id"], self.b_id, "identity must never be client-assignable"
        )
        self.assertEqual(me.json()["email"], self.a_email)

    async def test_user_cannot_raise_their_own_threat_threshold_out_of_range(self):
        # Not authorization, but the same class of trust: a value outside the
        # documented range would change when an automatic alarm fires.
        response = await self.client.patch(
            "/api/v1/users/me", json={"threat_threshold": 99.0}, headers=self.a
        )
        if response.status_code in (200, 204):
            me = await self.client.get("/api/v1/users/me", headers=self.a)
            threshold = me.json().get("threat_threshold")
            if isinstance(threshold, (int, float)):
                self.assertLessEqual(threshold, 1.0)

    # ------------------------------------------------------- mass assignment

    async def test_contact_cannot_be_created_into_another_account(self):
        created = await self.client.post(
            "/api/v1/users/me/emergency-contacts",
            json={
                "name": "Planted",
                "phone": "+15550101001",
                "relationship": "Sister",
                "email": "x@example.com",
                # The crafted part: try to make this belong to B.
                "user_id": self.b_id,
            },
            headers=self.a,
        )
        self.assertIn(created.status_code, (200, 201, 422), created.text)

        b_contacts = await self.client.get(
            "/api/v1/users/me/emergency-contacts", headers=self.b
        )
        self.assertEqual(
            [c["name"] for c in b_contacts.json()],
            [],
            "a user_id in the body must never place a row in another account",
        )

    async def test_incident_cannot_be_created_into_another_account(self):
        created = await self.client.post(
            "/api/v1/incidents/",
            json={"title": "Planted", "description": "x", "user_id": self.b_id},
            headers=self.a,
        )
        self.assertIn(created.status_code, (200, 201, 422), created.text)

        b_incidents = await self.client.get("/api/v1/incidents/", headers=self.b)
        rows = b_incidents.json()
        rows = rows if isinstance(rows, list) else rows.get("items", [])
        self.assertEqual(rows, [], "incidents must be owned by the caller, not the body")


class TestTokenSecurity(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://testserver"
        )
        self.settings = get_settings()
        email = f"token-{uuid4().hex}@safeherapp.com"
        await self.client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "password": "TestPass123!",
                "full_name": "Token Test",
                "phone": "+15550100000",
            },
        )
        login = await self.client.post(
            "/api/v1/auth/login", json={"email": email, "password": "TestPass123!"}
        )
        self.token = login.json()["access_token"]
        me = await self.client.get(
            "/api/v1/users/me", headers={"Authorization": f"Bearer {self.token}"}
        )
        self.user_id = me.json()["id"]

    async def asyncTearDown(self):
        await self.client.aclose()

    async def _get_me(self, token: str):
        return await self.client.get(
            "/api/v1/users/me", headers={"Authorization": f"Bearer {token}"}
        )

    async def test_unsigned_alg_none_token_is_rejected(self):
        # The classic JWT downgrade: claim "no algorithm" and send an empty
        # signature. Hand-assembled rather than produced with jwt.encode(),
        # because python-jose refuses to *emit* alg=none -- an attacker has no
        # such scruples, so the token is built byte by byte the way a real
        # one would be.
        def seg(raw: bytes) -> str:
            return base64.urlsafe_b64encode(raw).decode().rstrip("=")

        header = seg(json.dumps({"alg": "none", "typ": "JWT"}).encode())
        claims = seg(
            json.dumps(
                {
                    "sub": self.user_id,
                    "role": "admin",
                    "exp": int((datetime.now(timezone.utc) + timedelta(hours=1)).timestamp()),
                }
            ).encode()
        )
        forged = f"{header}.{claims}."

        response = await self._get_me(forged)
        self.assertIn(response.status_code, DENIED, response.text)

    async def test_token_signed_with_the_wrong_key_is_rejected(self):
        forged = jwt.encode(
            {
                "sub": self.user_id,
                "role": "admin",
                "exp": datetime.now(timezone.utc) + timedelta(hours=1),
            },
            key="not-the-real-signing-key",
            algorithm="HS256",
        )
        response = await self._get_me(forged)
        self.assertIn(response.status_code, DENIED, response.text)

    async def test_expired_token_is_rejected(self):
        expired = jwt.encode(
            {
                "sub": self.user_id,
                "role": "user",
                "exp": datetime.now(timezone.utc) - timedelta(hours=1),
            },
            key=self.settings.jwt_secret_key,
            algorithm="HS256",
        )
        response = await self._get_me(expired)
        self.assertIn(response.status_code, DENIED, response.text)

    async def test_token_for_a_nonexistent_subject_is_rejected(self):
        orphan = jwt.encode(
            {
                "sub": f"does-not-exist-{uuid4().hex}",
                "role": "user",
                "exp": datetime.now(timezone.utc) + timedelta(hours=1),
            },
            key=self.settings.jwt_secret_key,
            algorithm="HS256",
        )
        response = await self._get_me(orphan)
        self.assertIn(response.status_code, DENIED, response.text)

    async def test_role_claim_in_the_token_does_not_grant_admin(self):
        # Even correctly signed, a role claim must not be the source of truth
        # for authorization -- the database row is.
        elevated = jwt.encode(
            {
                "sub": self.user_id,
                "role": "admin",
                "exp": datetime.now(timezone.utc) + timedelta(hours=1),
            },
            key=self.settings.jwt_secret_key,
            algorithm="HS256",
        )
        response = await self._get_me(elevated)
        if response.status_code == 200:
            self.assertNotEqual(
                response.json().get("role"),
                "admin",
                "role must be read from the stored user, not the token claim",
            )

    async def test_malformed_and_missing_tokens_are_rejected(self):
        for bad in ("", "not-a-jwt", "a.b.c", "Bearer", "null"):
            response = await self._get_me(bad)
            self.assertIn(response.status_code, DENIED, f"{bad!r}: {response.text}")


if __name__ == "__main__":
    unittest.main()
