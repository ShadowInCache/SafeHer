"""An account cannot be created without accepting the terms.

The registration screen rendered "Terms of Service" and "Privacy Policy" as
tappable text whose handler raised a toast saying *"coming soon"*. There was no
checkbox, nothing to accept, and no column to record an acceptance in — so the
app collected a woman's location, microphone, camera and the phone numbers of
the people she would call for help, having never asked, and could not have
shown what she agreed to if anyone asked.

Consent is checked *before* the account exists. Creating it first and
collecting agreement later would mean holding that data on the strength of an
intention to ask.

The suite as a whole runs with enforcement off (see `conftest.py`) because
forty-five modules create accounts to get at something else. This file turns it
back on, which is why the coverage is deliberate rather than incidental.
"""

import unittest
from uuid import uuid4

import httpx
from sqlalchemy import select

from fastapi_app.config import get_settings
from fastapi_app.db import SessionLocal, init_db
from fastapi_app.main import app
from fastapi_app.models import User


class TermsAcceptanceTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self.settings = get_settings()
        self._was_required = self.settings.require_terms_acceptance
        self.settings.require_terms_acceptance = True
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://testserver"
        )

    async def asyncTearDown(self):
        self.settings.require_terms_acceptance = self._was_required
        await self.client.aclose()

    def _payload(self, **overrides):
        body = {
            "email": f"terms-{uuid4().hex[:10]}@safeherapp.com",
            "password": "TestPass123!",
            "full_name": "Terms Tester",
            "role": "user",
            "accepted_terms_version": self.settings.current_terms_version,
            "accepted_privacy_version": self.settings.current_privacy_version,
        }
        body.update(overrides)
        return body

    async def _register(self, **overrides):
        body = self._payload(**overrides)
        return body, await self.client.post("/api/v1/auth/register", json=body)

    async def _user(self, email):
        async with SessionLocal() as session:
            rows = await session.execute(select(User).where(User.email == email.lower()))
            return rows.scalars().first()

    # ------------------------------------------------------------- accepted

    async def test_accepting_both_creates_the_account(self):
        body, response = await self._register()

        self.assertEqual(response.status_code, 201, response.text)
        user = await self._user(body["email"])
        self.assertIsNotNone(user)

    async def test_the_accepted_versions_are_recorded(self):
        # "She agreed" is not an answer to "to what, and when". Versions make
        # re-consent possible after a policy changes; a boolean would not.
        body, _ = await self._register()

        user = await self._user(body["email"])
        self.assertEqual(user.terms_version, self.settings.current_terms_version)
        self.assertEqual(user.privacy_version, self.settings.current_privacy_version)
        self.assertIsNotNone(user.terms_accepted_at)

    # ------------------------------------------------------------- refused

    async def test_registering_without_accepting_is_refused(self):
        body, response = await self._register(
            accepted_terms_version=None, accepted_privacy_version=None
        )

        self.assertEqual(response.status_code, 422, response.text)
        self.assertIsNone(
            await self._user(body["email"]),
            "no account may exist for someone who never accepted",
        )

    async def test_accepting_only_the_terms_is_refused(self):
        body, response = await self._register(accepted_privacy_version=None)

        self.assertEqual(response.status_code, 422)
        self.assertIsNone(await self._user(body["email"]))

    async def test_accepting_only_the_privacy_policy_is_refused(self):
        body, response = await self._register(accepted_terms_version=None)

        self.assertEqual(response.status_code, 422)
        self.assertIsNone(await self._user(body["email"]))

    async def test_an_outdated_version_is_not_consent_to_the_current_one(self):
        # Accepting it silently would make the stored version a record of what
        # we served rather than what she was shown.
        body, response = await self._register(accepted_terms_version="1970-01-01")

        self.assertEqual(response.status_code, 422)
        self.assertIsNone(await self._user(body["email"]))

    async def test_the_refusal_names_the_documents(self):
        # The client has to be able to tell her what is being asked for.
        _, response = await self._register(accepted_terms_version=None)

        detail = response.text.lower()
        self.assertIn("terms", detail)
        self.assertIn("privacy", detail)

    # --------------------------------------------------------- the defaults

    async def test_enforcement_is_on_by_default(self):
        from fastapi_app.config import Settings

        self.assertTrue(
            Settings.model_fields["require_terms_acceptance"].default,
            "a deployment that forgets a variable must not stop asking for consent",
        )


if __name__ == "__main__":
    unittest.main()
