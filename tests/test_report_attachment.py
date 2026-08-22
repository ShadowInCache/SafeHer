"""The incident report, delivered to the people who were alerted.

A contact who receives an SOS gets a text message and a link. The link is
revocable and expires, which is right for access control and wrong for the
moment someone needs to forward what happened to a police officer or a lawyer.
So the report itself now travels with the follow-up email as a PDF.

**Why the follow-up and not the alert.** The alert leaves the instant the
countdown ends, while the recording is still being made. A report generated
then would read "No evidence was captured for this incident" and carry no
hashes, because there is nothing yet to hash — and rendering it would put PDF
generation, evidence decryption and SHA-256 hashing on the critical path of the
one request that must not wait. These tests pin that separation.
"""

from __future__ import annotations

import os
import unittest
from uuid import uuid4

os.environ.setdefault("DATABASE_URL", "sqlite:///./test_safeher.db")
os.environ.setdefault("ENABLE_MQTT_WORKER", "false")
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-key-change-me")

import httpx

from fastapi_app.config import get_settings
from fastapi_app.db import init_db
from fastapi_app.main import app
from fastapi_app.models import Incident, User
from fastapi_app.services.emergency_dispatch import (
    MAX_ATTACHMENT_BYTES,
    send_evidence_followup,
)
from fastapi_app.services.evidence_store import EvidenceStore, derive_key


class _CapturingEmailer:
    """Stands in for Brevo/SMTP and records what it was asked to send."""

    is_configured = True

    def __init__(self):
        self.sent = []

    async def send(self, *, to, subject, html_body, attachments=None):
        self.sent.append(
            {"to": to, "subject": subject, "body": html_body, "attachments": attachments}
        )
        return "message-id"


class _UnreadableStore:
    """A store whose reads fail, to prove a broken report does not stop mail."""

    def read(self, storage_id):
        raise RuntimeError("storage is unreachable")


class TestReportAttachment(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://testserver"
        )
        self.settings = get_settings()
        self.email = f"report-{uuid4().hex}@safeherapp.com"
        self.headers = {"Authorization": f"Bearer {await self._login()}"}
        self.store = EvidenceStore(
            key=derive_key("attachment-test"), directory="./evidence_store"
        )

    async def asyncTearDown(self):
        await self.client.aclose()

    async def _login(self) -> str:
        await self.client.post(
            "/api/v1/auth/register",
            json={
                "email": self.email,
                "password": "TestPass123!",
                "full_name": "Priya Patel",
                "role": "user",
            },
        )
        login = await self.client.post(
            "/api/v1/auth/login", json={"email": self.email, "password": "TestPass123!"}
        )
        return login.json()["access_token"]

    async def _incident_with_contact(self):
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
        created = await self.client.post(
            "/api/v1/alerts/emergency",
            headers=self.headers,
            json={
                "severity": "critical",
                "summary": "SOS",
                "location": {"latitude": 12.85, "longitude": 77.68},
            },
        )
        return created.json()["id"]

    async def _session_and_user(self):
        from fastapi_app.db import SessionLocal
        from sqlalchemy import select

        session = SessionLocal()
        user = (
            await session.execute(select(User).where(User.email == self.email))
        ).scalars().first()
        return session, user

    async def test_the_followup_carries_the_report_as_a_pdf(self):
        incident_id = await self._incident_with_contact()
        session, user = await self._session_and_user()
        emailer = _CapturingEmailer()

        try:
            await send_evidence_followup(
                session=session,
                settings=self.settings,
                user=user,
                incident_id=incident_id,
                share_url="https://example.test/share/tok",
                email_sender=emailer,
                evidence_store=self.store,
            )
        finally:
            await session.close()

        self.assertEqual(len(emailer.sent), 1)
        attachments = emailer.sent[0]["attachments"]
        self.assertIsNotNone(attachments, "the report was not attached")
        name, content = attachments[0]
        self.assertTrue(name.endswith(".pdf"), name)
        self.assertIn(incident_id, name)
        # A real PDF, not an empty placeholder.
        self.assertTrue(content.startswith(b"%PDF"))
        self.assertGreater(len(content), 500)

    async def test_the_share_link_still_travels_with_it(self):
        """The attachment supplements the link, it does not replace it. The
        link is how a contact reaches the recording itself, which the report
        only hashes."""
        incident_id = await self._incident_with_contact()
        session, user = await self._session_and_user()
        emailer = _CapturingEmailer()

        try:
            await send_evidence_followup(
                session=session,
                settings=self.settings,
                user=user,
                incident_id=incident_id,
                share_url="https://example.test/share/tok",
                email_sender=emailer,
                evidence_store=self.store,
            )
        finally:
            await session.close()

        self.assertIn("https://example.test/share/tok", emailer.sent[0]["body"])

    async def test_a_report_that_cannot_be_built_does_not_stop_the_email(self):
        """A contact told nothing is worse off than a contact told something
        without a PDF stapled to it."""
        incident_id = await self._incident_with_contact()
        session, user = await self._session_and_user()
        emailer = _CapturingEmailer()

        try:
            await send_evidence_followup(
                session=session,
                settings=self.settings,
                user=user,
                incident_id=incident_id,
                share_url="https://example.test/share/tok",
                email_sender=emailer,
                # Store that raises on every read.
                evidence_store=_UnreadableStore(),
            )
        finally:
            await session.close()

        self.assertEqual(len(emailer.sent), 1, "the email was lost with the report")
        self.assertIn("https://example.test/share/tok", emailer.sent[0]["body"])

    async def test_no_store_means_no_attachment_but_still_an_email(self):
        incident_id = await self._incident_with_contact()
        session, user = await self._session_and_user()
        emailer = _CapturingEmailer()

        try:
            await send_evidence_followup(
                session=session,
                settings=self.settings,
                user=user,
                incident_id=incident_id,
                share_url="https://example.test/share/tok",
                email_sender=emailer,
            )
        finally:
            await session.close()

        self.assertEqual(len(emailer.sent), 1)
        self.assertIsNone(emailer.sent[0]["attachments"])

    async def test_the_size_cap_is_below_what_mail_providers_reject(self):
        """Gmail bounces over 25MB, and a bounce loses the whole message --
        alert, link and all -- not just the attachment."""
        self.assertLess(MAX_ATTACHMENT_BYTES, 25 * 1024 * 1024)


if __name__ == "__main__":
    unittest.main()
