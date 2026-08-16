"""Contract tests for what the Firebase sign-in exchange actually persists.

Firebase itself only holds displayName / email / photoURL. The phone number a
user types during sign-up exists nowhere except the sign-up form, so the client
has to send it on exchange or the provisioned profile silently loses it. These
tests pin that behaviour down.
"""

from __future__ import annotations

import os
import unittest
from unittest.mock import patch
from uuid import uuid4

os.environ["DATABASE_URL"] = "sqlite:///./test_safeher.db"
os.environ["ENABLE_MQTT_WORKER"] = "false"
os.environ["JWT_SECRET_KEY"] = "test-secret-key-change-me"
os.environ["LOG_LEVEL"] = "WARNING"

import httpx

from fastapi_app.db import init_db
from fastapi_app.main import app
from fastapi_app.services.firebase_auth import FirebaseIdentity


class TestFirebaseProvisioning(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://testserver",
        )

    async def asyncTearDown(self):
        await self.client.aclose()

    @staticmethod
    def _identity(
        email: str, name: str | None = "Google User", *, email_verified: bool = True
    ) -> FirebaseIdentity:
        uid = f"uid-{uuid4().hex}"
        return FirebaseIdentity(
            uid=uid,
            email=email,
            name=name,
            raw_claims={"uid": uid, "email": email, "email_verified": email_verified},
            email_verified=email_verified,
        )

    async def _me(self, token: str) -> dict:
        response = await self.client.get(
            "/api/v1/users/me", headers={"Authorization": f"Bearer {token}"}
        )
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    @patch("fastapi_app.routers.auth.verify_firebase_id_token")
    async def test_first_sign_in_persists_name_phone_and_avatar(self, mocked_verify):
        email = f"signup-{uuid4().hex}@safeherapp.com"
        mocked_verify.return_value = self._identity(email)

        exchange = await self.client.post(
            "/api/v1/auth/firebase/exchange",
            json={
                "id_token": "header.payload.signature",
                "full_name": "Asha Menon",
                "phone": "+919876543210",
                "avatar_url": "https://example.com/a.png",
            },
        )
        self.assertEqual(exchange.status_code, 200, exchange.text)

        profile = await self._me(exchange.json()["access_token"])
        self.assertEqual(profile["email"], email)
        self.assertEqual(profile["full_name"], "Asha Menon")
        self.assertEqual(profile["phone"], "+919876543210")
        self.assertEqual(profile["avatar_url"], "https://example.com/a.png")

    @patch("fastapi_app.routers.auth.verify_firebase_id_token")
    async def test_second_sign_in_reuses_the_same_account(self, mocked_verify):
        email = f"repeat-{uuid4().hex}@safeherapp.com"

        mocked_verify.return_value = self._identity(email)
        first = await self.client.post(
            "/api/v1/auth/firebase/exchange",
            json={"id_token": "header.payload.signature", "full_name": "Asha Menon", "phone": "+919876543210"},
        )
        first_id = (await self._me(first.json()["access_token"]))["id"]

        mocked_verify.return_value = self._identity(email)
        second = await self.client.post(
            "/api/v1/auth/firebase/exchange", json={"id_token": "header.payload.signature"}
        )
        second_profile = await self._me(second.json()["access_token"])

        self.assertEqual(second_profile["id"], first_id, "signing in again must not fork the account")
        self.assertEqual(second_profile["phone"], "+919876543210")

    @patch("fastapi_app.routers.auth.verify_firebase_id_token")
    async def test_exchange_backfills_but_never_overwrites_edited_details(self, mocked_verify):
        email = f"edit-{uuid4().hex}@safeherapp.com"

        mocked_verify.return_value = self._identity(email, name=None)
        created = await self.client.post(
            "/api/v1/auth/firebase/exchange", json={"id_token": "header.payload.signature"}
        )
        token = created.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        # The user edits their profile in-app.
        edited = await self.client.patch(
            "/api/v1/users/me",
            headers=headers,
            json={"full_name": "Preferred Name", "phone": "+911112223334"},
        )
        self.assertEqual(edited.status_code, 200, edited.text)

        # Signing in again must not clobber what they chose.
        mocked_verify.return_value = self._identity(email, name="Google Display Name")
        again = await self.client.post(
            "/api/v1/auth/firebase/exchange",
            json={"id_token": "header.payload.signature", "full_name": "Google Display Name", "phone": "+915556667778"},
        )
        profile = await self._me(again.json()["access_token"])

        self.assertEqual(profile["full_name"], "Preferred Name")
        self.assertEqual(profile["phone"], "+911112223334")

    @patch("fastapi_app.routers.auth.verify_firebase_id_token")
    async def test_exchange_works_without_optional_details(self, mocked_verify):
        email = f"minimal-{uuid4().hex}@safeherapp.com"
        mocked_verify.return_value = self._identity(email, name=None)

        exchange = await self.client.post(
            "/api/v1/auth/firebase/exchange", json={"id_token": "header.payload.signature"}
        )
        self.assertEqual(exchange.status_code, 200, exchange.text)

        profile = await self._me(exchange.json()["access_token"])
        self.assertEqual(profile["email"], email)
        self.assertIsNone(profile["phone"])

    @patch("fastapi_app.routers.auth.verify_firebase_id_token")
    async def test_provisioned_account_can_immediately_use_other_features(self, mocked_verify):
        """A Google-provisioned user must be a first-class account, not a stub."""
        email = f"usable-{uuid4().hex}@safeherapp.com"
        mocked_verify.return_value = self._identity(email)

        exchange = await self.client.post(
            "/api/v1/auth/firebase/exchange",
            json={"id_token": "header.payload.signature", "full_name": "Asha Menon"},
        )
        headers = {"Authorization": f"Bearer {exchange.json()['access_token']}"}

        contact = await self.client.post(
            "/api/v1/users/me/emergency-contacts",
            headers=headers,
            json={"name": "Mum", "phone": "+919999999999", "priority": 1},
        )
        self.assertEqual(contact.status_code, 201, contact.text)

        prefs = await self.client.get("/api/v1/safety/preferences", headers=headers)
        self.assertEqual(prefs.status_code, 200, prefs.text)

    @patch("fastapi_app.routers.auth.verify_firebase_id_token")
    async def test_google_sign_in_counts_as_a_verified_address(self, mocked_verify):
        """Found on a real device, in a real log.

        `firebase_exchange` provisioned every account with `is_verified`
        False. That is invisible while the user keeps signing in with
        Google -- the exchange never checks it -- but `/auth/login` does,
        and answers 403 "check your inbox for the verification code" the
        moment SMTP is configured. No code was ever sent, because the user
        never registered by email, so the account is simply locked.
        """
        email = f"verified-{uuid4().hex}@safeherapp.com"
        mocked_verify.return_value = self._identity(email)

        response = await self.client.post(
            "/api/v1/auth/firebase/exchange", json={"id_token": "firebase-id-token-stub"}
        )

        self.assertEqual(response.status_code, 200, response.text)
        self.assertTrue((await self._me(response.json()["access_token"]))["is_verified"])

    @patch("fastapi_app.routers.auth.verify_firebase_id_token")
    async def test_an_unverified_provider_address_is_not_promoted(self, mocked_verify):
        # The claim is the provider's assertion, not a formality. An address
        # Google itself will not vouch for must not clear SafeHer's check.
        email = f"unverified-{uuid4().hex}@safeherapp.com"
        mocked_verify.return_value = self._identity(email, email_verified=False)

        response = await self.client.post(
            "/api/v1/auth/firebase/exchange", json={"id_token": "firebase-id-token-stub"}
        )

        self.assertEqual(response.status_code, 200, response.text)
        self.assertFalse((await self._me(response.json()["access_token"]))["is_verified"])

    @patch("fastapi_app.routers.auth.verify_firebase_id_token")
    async def test_an_older_unverified_account_is_repaired_on_next_sign_in(self, mocked_verify):
        """Accounts already provisioned before the fix must heal themselves.

        Requiring a support request, or a password reset the user cannot
        start because they have no password, would leave them stranded.
        """
        email = f"legacy-{uuid4().hex}@safeherapp.com"
        mocked_verify.return_value = self._identity(email, email_verified=False)
        first = await self.client.post(
            "/api/v1/auth/firebase/exchange", json={"id_token": "firebase-id-token-stub"}
        )
        self.assertFalse((await self._me(first.json()["access_token"]))["is_verified"])

        # Same address, this time with Google vouching for it.
        mocked_verify.return_value = self._identity(email, email_verified=True)
        second = await self.client.post(
            "/api/v1/auth/firebase/exchange", json={"id_token": "firebase-id-token-stub"}
        )

        self.assertTrue((await self._me(second.json()["access_token"]))["is_verified"])

    @patch("fastapi_app.routers.auth.verify_firebase_id_token")
    async def test_google_sign_in_unblocks_a_login_stranded_by_verification(self, mocked_verify):
        """The reachable form of the bug, end to end.

        Register by email while verification is enforced and the account
        starts unverified, holding a code in an inbox. Sign in with Google
        instead -- which proves ownership of that same address far more
        strongly than the code would -- and before the fix the password
        login stayed 403 forever, because the exchange never touched
        `is_verified`. The user has proven who they are and is still locked
        out, with no error that explains why.
        """
        from fastapi_app.config import Settings, get_settings

        base = get_settings()
        strict = Settings(**{**base.model_dump(), "require_email_verification": True})
        app.dependency_overrides[get_settings] = lambda: strict
        try:
            email = f"stranded-{uuid4().hex}@safeherapp.com"
            credentials = {"email": email, "password": "TestPass123!"}
            register = await self.client.post(
                "/api/v1/auth/register", json={**credentials, "full_name": "S", "role": "user"}
            )
            self.assertEqual(register.status_code, 201, register.text)

            blocked = await self.client.post("/api/v1/auth/login", json=credentials)
            self.assertEqual(blocked.status_code, 403, blocked.text)
            self.assertIn("not verified", blocked.text)

            mocked_verify.return_value = self._identity(email)
            exchange = await self.client.post(
                "/api/v1/auth/firebase/exchange", json={"id_token": "firebase-id-token-stub"}
            )
            self.assertEqual(exchange.status_code, 200, exchange.text)

            unblocked = await self.client.post("/api/v1/auth/login", json=credentials)
            self.assertEqual(unblocked.status_code, 200, unblocked.text)
        finally:
            app.dependency_overrides.pop(get_settings, None)

    async def test_a_forged_token_is_rejected(self):
        response = await self.client.post(
            "/api/v1/auth/firebase/exchange", json={"id_token": "not.a.real.token"}
        )
        self.assertIn(response.status_code, {401, 503}, response.text)


if __name__ == "__main__":
    unittest.main()
