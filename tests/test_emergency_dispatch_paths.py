"""The parts of an emergency dispatch that only run when something is wrong.

The happy path is covered elsewhere. What was not covered is everything that
happens when a channel is missing, a contact is unreachable, or a send fails
partway — which is most of what actually happens in the field, and the code
whose behaviour a frightened person depends on.

The governing rule for this module: it never raises. The incident is already
recorded and someone is waiting on a response, so a partial failure is
reported rather than thrown. Every test here exists to hold that line.
"""

from __future__ import annotations

import os
import unittest
from uuid import uuid4

os.environ["DATABASE_URL"] = "sqlite:///./test_safeher.db"
os.environ["ENABLE_MQTT_WORKER"] = "false"
os.environ["JWT_SECRET_KEY"] = "test-secret-key-change-me"
os.environ["LOG_LEVEL"] = "WARNING"

from sqlalchemy import select

from fastapi_app.config import get_settings
from fastapi_app.db import SessionLocal, init_db
from fastapi_app.models import EmergencyContact, NotificationLog, User
from fastapi_app.services.emergency_dispatch import (
    build_evidence_followup_email,
    dispatch_to_contacts,
    send_evidence_followup,
)


class _Emailer:
    """Stands in for whichever email channel is configured."""

    def __init__(self, *, configured: bool = True, fails: bool = False):
        self.is_configured = configured
        self._fails = fails
        self.sent: list[tuple[str, str]] = []

    async def send(self, *, to: str, subject: str, html_body: str, attachments=None) -> None:
        if self._fails:
            raise RuntimeError("smtp said no")
        self.sent.append((to, subject))


class _Sms:
    def __init__(self, *, configured: bool = False):
        self.is_configured = configured
        self.sent: list[str] = []

    async def send(self, *, to: str, body: str) -> None:
        self.sent.append(to)


class DispatchCase(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self.settings = get_settings()
        self.session = SessionLocal()
        self.user = User(
            id=str(uuid4()),
            email=f"owner-{uuid4().hex[:8]}@safeherapp.com",
            password_hash="x",
            full_name="Priya Patel",
        )
        self.session.add(self.user)
        await self.session.commit()

    async def asyncTearDown(self):
        await self.session.close()

    async def _contact(self, *, name="Amma", email=None, phone="+919876543210") -> EmergencyContact:
        # `phone` is NOT NULL in the schema: every contact has a number, and
        # the email is the optional half. That makes "no email while SMS is
        # unconfigured" the realistic unreachable case, not a contrived one.
        contact = EmergencyContact(
            id=str(uuid4()),
            user_id=self.user.id,
            name=name,
            email=email,
            phone=phone,
            priority=1,
        )
        self.session.add(contact)
        await self.session.commit()
        return contact

    async def _logs(self) -> list[NotificationLog]:
        rows = await self.session.execute(
            select(NotificationLog).where(NotificationLog.user_id == self.user.id)
        )
        return list(rows.scalars())


class TestNoContacts(DispatchCase):
    async def test_a_user_with_no_contacts_reports_zero_rather_than_failing(self):
        # The worst possible moment to raise. The incident row already exists
        # and the caller still has to answer someone in an emergency.
        report = await dispatch_to_contacts(
            session=self.session,
            settings=self.settings,
            user=self.user,
            incident_id=str(uuid4()),
        )

        self.assertEqual(report.contacts_total, 0)
        self.assertEqual(report.contacts_notified, 0)
        self.assertEqual(report.reached_contact_ids, [])
        self.assertEqual(report.results, [])


class TestUnreachableContacts(DispatchCase):
    async def test_a_contact_with_no_email_is_reported_not_skipped_silently(self):
        # A contact stored with only a phone number, while SMS is
        # unconfigured, is unreachable. The user has to be able to find that
        # out — she believes that person was told.
        await self._contact(email=None)

        report = await dispatch_to_contacts(
            session=self.session,
            settings=self.settings,
            user=self.user,
            incident_id=str(uuid4()),
            email_sender=_Emailer(),
            sms_sender=_Sms(configured=False),
        )

        self.assertEqual(report.contacts_total, 1)
        self.assertEqual(report.contacts_notified, 0)
        self.assertTrue(report.results[0].failures)

    async def test_an_unconfigured_email_channel_is_named_as_the_reason(self):
        await self._contact(email="amma@example.com")

        report = await dispatch_to_contacts(
            session=self.session,
            settings=self.settings,
            user=self.user,
            incident_id=str(uuid4()),
            email_sender=_Emailer(configured=False),
            sms_sender=_Sms(configured=False),
        )

        failure = report.results[0].failures.get("email", "")
        self.assertIn("configured", failure.lower())

    async def test_a_failing_send_does_not_stop_the_remaining_contacts(self):
        # Fan-out, not a chain. One bad address must not cost the other four
        # people their alert.
        for i in range(3):
            await self._contact(name=f"Contact {i}", email=f"c{i}@example.com")

        report = await dispatch_to_contacts(
            session=self.session,
            settings=self.settings,
            user=self.user,
            incident_id=str(uuid4()),
            email_sender=_Emailer(fails=True),
            sms_sender=_Sms(configured=False),
        )

        self.assertEqual(report.contacts_total, 3)
        self.assertEqual(report.contacts_notified, 0)
        # Every contact was attempted and every outcome recorded, rather than
        # the fan-out aborting on the first exception.
        self.assertEqual(len(report.results), 3)


class TestSuccessIsRecorded(DispatchCase):
    async def test_a_delivered_alert_is_logged_against_the_contact(self):
        # The report is what the app shows as "Notified". If the log and the
        # report disagree, one of them is lying to the user.
        contact = await self._contact(email="amma@example.com")
        emailer = _Emailer()

        report = await dispatch_to_contacts(
            session=self.session,
            settings=self.settings,
            user=self.user,
            incident_id=str(uuid4()),
            email_sender=emailer,
            sms_sender=_Sms(configured=False),
            latitude=12.85,
            longitude=77.68,
        )

        self.assertEqual(report.contacts_notified, 1)
        self.assertIn(contact.id, report.reached_contact_ids)
        self.assertEqual(len(emailer.sent), 1)
        self.assertEqual(emailer.sent[0][0], "amma@example.com")

    async def test_every_attempt_leaves_an_audit_row(self):
        await self._contact(email="amma@example.com")

        await dispatch_to_contacts(
            session=self.session,
            settings=self.settings,
            user=self.user,
            incident_id=str(uuid4()),
            email_sender=_Emailer(),
            sms_sender=_Sms(configured=False),
        )

        self.assertTrue(await self._logs())


class TestEvidenceFollowup(DispatchCase):
    """FR-EMG-05's second message, carrying the recording's link.

    The alert itself goes the instant the countdown ends, while the recording
    is still uploading, so the URL cannot be in it without delaying the thing
    that matters.
    """

    async def test_only_contacts_with_an_email_receive_it(self):
        await self._contact(name="Amma", email="amma@example.com")
        await self._contact(name="Ravi", email=None)
        emailer = _Emailer()

        report = await send_evidence_followup(
            session=self.session,
            settings=self.settings,
            user=self.user,
            incident_id=str(uuid4()),
            share_url="https://example.test/s/abc",
            email_sender=emailer,
        )

        self.assertEqual(report.contacts_total, 2)
        self.assertEqual(report.contacts_notified, 1)
        self.assertEqual(len(emailer.sent), 1)

    async def test_no_contacts_is_not_an_error(self):
        report = await send_evidence_followup(
            session=self.session,
            settings=self.settings,
            user=self.user,
            incident_id=str(uuid4()),
            share_url="https://example.test/s/abc",
            email_sender=_Emailer(),
        )

        self.assertEqual(report.contacts_total, 0)

    async def test_a_failing_send_is_reported_not_raised(self):
        await self._contact(email="amma@example.com")

        report = await send_evidence_followup(
            session=self.session,
            settings=self.settings,
            user=self.user,
            incident_id=str(uuid4()),
            share_url="https://example.test/s/abc",
            email_sender=_Emailer(fails=True),
        )

        self.assertEqual(report.contacts_notified, 0)
        self.assertTrue(report.results[0].failures)


class TestFollowupEmailBody(unittest.TestCase):
    def test_the_share_url_survives_intact(self):
        body = build_evidence_followup_email(
            user_name="Priya", contact_name="Amma", share_url="https://example.test/s/abc123"
        )

        self.assertIn("https://example.test/s/abc123", body)

    def test_a_name_cannot_inject_markup(self):
        # A display name is user-supplied and lands in an HTML email. Contacts
        # open these in a hurry; an injected link is a phishing vector aimed
        # at someone already alarmed.
        body = build_evidence_followup_email(
            user_name="<script>alert(1)</script>",
            contact_name="Amma",
            share_url="https://example.test/s/abc",
        )

        self.assertNotIn("<script>", body)
        self.assertIn("&lt;script&gt;", body)

    def test_a_hostile_share_url_is_escaped(self):
        body = build_evidence_followup_email(
            user_name="Priya",
            contact_name="Amma",
            share_url='https://x.test/"><a href="https://evil.test">click</a>',
        )

        self.assertNotIn('<a href="https://evil.test"', body)


if __name__ == "__main__":
    unittest.main()
