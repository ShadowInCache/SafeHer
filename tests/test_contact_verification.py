"""Contract tests for emergency-contact verification — SRS FR-EMG-10.

The failure this guards against is mundane and common: a mistyped address
that nobody notices until the day an alert goes to a stranger's inbox and
the person who could have helped hears nothing.

Two design decisions are asserted here as hard contract, because both are
easy to "fix" in the wrong direction later: an unverified contact is still
notified (a possibly-wrong address beats no address when someone is in
danger), and changing an address drops its verification (a tick earned at
one address says nothing about another).
"""

from __future__ import annotations

import os
import unittest
from datetime import datetime, timedelta
from uuid import uuid4

os.environ["DATABASE_URL"] = "sqlite:///./test_safeher.db"
os.environ["ENABLE_MQTT_WORKER"] = "false"
os.environ["JWT_SECRET_KEY"] = "test-secret-key-change-me"
os.environ["LOG_LEVEL"] = "WARNING"

import httpx
from sqlalchemy import select

from fastapi_app.config import Settings
from fastapi_app.db import SessionLocal, init_db
from fastapi_app.main import app
from fastapi_app.models import EmergencyContact, User
from fastapi_app.routers.users import MAX_EMERGENCY_CONTACTS
from fastapi_app.services.contact_verification import (
    MAX_ATTEMPTS,
    ContactVerificationError,
    build_verification_email,
    confirm_verification_code,
    send_verification_code,
)
from fastapi_app.services.emergency_dispatch import dispatch_to_contacts


class CapturingEmailSender:
    """Captures what would have been emailed, so a test can read the code."""

    def __init__(self, *, configured: bool = True):
        self.configured = configured
        self.sent: list[tuple[str, str, str]] = []

    @property
    def is_configured(self) -> bool:
        return self.configured

    async def send(self, *, to: str, subject: str, html_body: str) -> str:
        self.sent.append((to, subject, html_body))
        return "sent"

    @property
    def last_code(self) -> str:
        import re

        match = re.search(r"letter-spacing:6px;\s*\n?font-family:[^>]*>(\d{4,10})<", self.sent[-1][2])
        if match:
            return match.group(1)
        # Fall back to the first standalone digit run in the body.
        return re.findall(r">(\d{4,10})<", self.sent[-1][2])[0]


class TestVerificationEmail(unittest.TestCase):
    def test_the_email_explains_who_and_why(self):
        subject, body = build_verification_email(
            user_name="Priya Patel", contact_name="Anika", code="123456"
        )

        # The recipient may never have heard of SafeHer. An unexplained code
        # from an unknown sender reads as phishing and gets deleted.
        self.assertIn("Priya Patel", subject)
        self.assertIn("Anika", body)
        self.assertIn("123456", body)
        self.assertIn("emergency contact", body.lower())

    def test_names_are_escaped(self):
        _, body = build_verification_email(
            user_name="<script>x</script>", contact_name="Anika", code="123456"
        )

        self.assertNotIn("<script>", body)


class TestContactVerification(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://testserver"
        )
        self.email = f"contacts-{uuid4().hex}@safeherapp.com"
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

    async def _add_contact(self, *, email: str | None = "anika@example.com", headers=None) -> dict:
        payload = {
            "name": "Anika",
            "phone": f"+9111111{uuid4().int % 100000:05d}",
            "relationship": "Sister",
            "priority": 1,
        }
        if email:
            payload["email"] = email
        response = await self.client.post(
            "/api/v1/users/me/emergency-contacts",
            headers=headers or self.headers,
            json=payload,
        )
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()

    async def _row(self, contact_id: str) -> EmergencyContact:
        async with SessionLocal() as session:
            return await session.get(EmergencyContact, contact_id)

    async def _issue_code(self, contact_id: str) -> str:
        sender = CapturingEmailSender()
        async with SessionLocal() as session:
            contact = await session.get(EmergencyContact, contact_id)
            await send_verification_code(
                session,
                settings=Settings(),
                contact=contact,
                user_name="Priya Patel",
                email_sender=sender,
            )
        return sender.last_code

    # ------------------------------------------------------------ the cap

    async def test_the_contact_list_is_capped_at_ten(self):
        for _ in range(MAX_EMERGENCY_CONTACTS):
            await self._add_contact()

        response = await self.client.post(
            "/api/v1/users/me/emergency-contacts",
            headers=self.headers,
            json={"name": "Eleven", "phone": "+919999999999", "relationship": "F", "priority": 1},
        )

        self.assertEqual(response.status_code, 409, response.text)

    # -------------------------------------------------------- issuing a code

    async def test_a_new_contact_starts_unverified(self):
        contact = await self._add_contact()

        self.assertIsNone(contact["verified_at"])

    async def test_a_code_is_emailed_to_the_contact(self):
        contact = await self._add_contact()
        sender = CapturingEmailSender()

        async with SessionLocal() as session:
            row = await session.get(EmergencyContact, contact["id"])
            await send_verification_code(
                session,
                settings=Settings(),
                contact=row,
                user_name="Priya Patel",
                email_sender=sender,
            )

        self.assertEqual(len(sender.sent), 1)
        self.assertEqual(sender.sent[0][0], "anika@example.com")

    async def test_a_contact_without_an_email_cannot_be_verified(self):
        contact = await self._add_contact(email=None)

        async with SessionLocal() as session:
            row = await session.get(EmergencyContact, contact["id"])
            with self.assertRaises(ContactVerificationError):
                await send_verification_code(
                    session,
                    settings=Settings(),
                    contact=row,
                    user_name="Priya",
                    email_sender=CapturingEmailSender(),
                )

    async def test_no_email_channel_means_no_silent_success(self):
        contact = await self._add_contact()

        async with SessionLocal() as session:
            row = await session.get(EmergencyContact, contact["id"])
            # A user told "code sent" when nothing was sent will sit waiting.
            with self.assertRaises(ContactVerificationError):
                await send_verification_code(
                    session,
                    settings=Settings(),
                    contact=row,
                    user_name="Priya",
                    email_sender=CapturingEmailSender(configured=False),
                )

    async def test_a_failed_send_leaves_no_live_code_behind(self):
        contact = await self._add_contact()

        async with SessionLocal() as session:
            row = await session.get(EmergencyContact, contact["id"])
            with self.assertRaises(ContactVerificationError):
                await send_verification_code(
                    session,
                    settings=Settings(),
                    contact=row,
                    user_name="Priya",
                    email_sender=CapturingEmailSender(configured=False),
                )

        # Otherwise the attempt counter starts burning down on a code the
        # contact never received.
        row = await self._row(contact["id"])
        self.assertIsNone(row.verification_code_hash)

    async def test_only_the_hash_is_stored(self):
        contact = await self._add_contact()
        code = await self._issue_code(contact["id"])

        row = await self._row(contact["id"])
        self.assertIsNotNone(row.verification_code_hash)
        self.assertNotIn(code, row.verification_code_hash)

    # ------------------------------------------------------- confirming it

    async def test_the_right_code_verifies_the_contact(self):
        contact = await self._add_contact()
        code = await self._issue_code(contact["id"])

        response = await self.client.post(
            f"/api/v1/users/me/emergency-contacts/{contact['id']}/verify",
            headers=self.headers,
            json={"code": code},
        )

        self.assertEqual(response.status_code, 200, response.text)
        self.assertIsNotNone(response.json()["verified_at"])

    async def test_a_wrong_code_is_refused_and_counted(self):
        contact = await self._add_contact()
        await self._issue_code(contact["id"])

        response = await self.client.post(
            f"/api/v1/users/me/emergency-contacts/{contact['id']}/verify",
            headers=self.headers,
            json={"code": "000000"},
        )

        self.assertEqual(response.status_code, 400, response.text)
        row = await self._row(contact["id"])
        self.assertEqual(row.verification_attempts, 1)
        self.assertIsNone(row.verified_at)

    async def test_the_code_space_cannot_be_walked(self):
        contact = await self._add_contact()
        code = await self._issue_code(contact["id"])

        async with SessionLocal() as session:
            row = await session.get(EmergencyContact, contact["id"])
            row.verification_attempts = MAX_ATTEMPTS
            await session.commit()

        async with SessionLocal() as session:
            row = await session.get(EmergencyContact, contact["id"])
            # Even the correct code is refused once the budget is spent.
            with self.assertRaises(ContactVerificationError):
                await confirm_verification_code(session, contact=row, code=code)

    async def test_an_expired_code_is_refused(self):
        contact = await self._add_contact()
        code = await self._issue_code(contact["id"])

        async with SessionLocal() as session:
            row = await session.get(EmergencyContact, contact["id"])
            row.verification_expires_at = datetime.utcnow() - timedelta(minutes=1)
            await session.commit()

        async with SessionLocal() as session:
            row = await session.get(EmergencyContact, contact["id"])
            with self.assertRaises(ContactVerificationError):
                await confirm_verification_code(session, contact=row, code=code)

    async def test_a_code_cannot_be_replayed(self):
        contact = await self._add_contact()
        code = await self._issue_code(contact["id"])

        first = await self.client.post(
            f"/api/v1/users/me/emergency-contacts/{contact['id']}/verify",
            headers=self.headers,
            json={"code": code},
        )
        self.assertEqual(first.status_code, 200, first.text)

        second = await self.client.post(
            f"/api/v1/users/me/emergency-contacts/{contact['id']}/verify",
            headers=self.headers,
            json={"code": code},
        )
        self.assertEqual(second.status_code, 400, second.text)

    async def test_verifying_before_a_code_was_sent_is_refused(self):
        contact = await self._add_contact()

        response = await self.client.post(
            f"/api/v1/users/me/emergency-contacts/{contact['id']}/verify",
            headers=self.headers,
            json={"code": "123456"},
        )

        self.assertEqual(response.status_code, 400, response.text)

    # ---------------------------------------------------- changing the email

    async def test_changing_the_address_drops_verification(self):
        contact = await self._add_contact()
        code = await self._issue_code(contact["id"])
        await self.client.post(
            f"/api/v1/users/me/emergency-contacts/{contact['id']}/verify",
            headers=self.headers,
            json={"code": code},
        )

        updated = await self.client.put(
            f"/api/v1/users/me/emergency-contacts/{contact['id']}",
            headers=self.headers,
            json={"email": "someone-else@example.com"},
        )

        # A tick earned at one address says nothing about another, and
        # leaving it would hide the typo this feature exists to catch.
        self.assertEqual(updated.status_code, 200, updated.text)
        self.assertIsNone(updated.json()["verified_at"])

    async def test_an_unrelated_edit_keeps_verification(self):
        contact = await self._add_contact()
        code = await self._issue_code(contact["id"])
        await self.client.post(
            f"/api/v1/users/me/emergency-contacts/{contact['id']}/verify",
            headers=self.headers,
            json={"code": code},
        )

        updated = await self.client.put(
            f"/api/v1/users/me/emergency-contacts/{contact['id']}",
            headers=self.headers,
            json={"relationship": "Best friend"},
        )

        self.assertIsNotNone(updated.json()["verified_at"])

    # ------------------------------------------------------------ ownership

    async def test_another_user_cannot_verify_your_contact(self):
        contact = await self._add_contact()
        other = {"Authorization": f"Bearer {await self._login(f'other-{uuid4().hex}@safeherapp.com')}"}

        for path in ("verify/send", "verify"):
            response = await self.client.post(
                f"/api/v1/users/me/emergency-contacts/{contact['id']}/{path}",
                headers=other,
                json={"code": "123456"},
            )
            self.assertEqual(response.status_code, 404, response.text)

    # --------------------------------------------- unverified still notified

    async def test_an_unverified_contact_is_still_alerted(self):
        # The decision worth pinning: verification tells the user which
        # entries to double-check. It is not a gate on getting help, because
        # a possibly-wrong address still beats no address in an emergency.
        contact = await self._add_contact()
        emailer = CapturingEmailSender()

        async with SessionLocal() as session:
            user = (
                (await session.execute(select(User).where(User.email == self.email)))
                .scalars()
                .one()
            )
            report = await dispatch_to_contacts(
                session=session,
                settings=Settings(),
                user=user,
                incident_id="incident-1",
                email_sender=emailer,
            )

        row = await self._row(contact["id"])
        self.assertIsNone(row.verified_at)
        self.assertEqual(report.contacts_notified, 1)


if __name__ == "__main__":
    unittest.main()
