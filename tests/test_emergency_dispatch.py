"""Contract tests for the emergency fan-out — SRS FR-EMG-04 and FR-EMG-05.

These cover the requirement the product exists for: when an SOS fires, the
people who can help are told. Until this landed, `POST /alerts/emergency`
recorded an incident and notified the *triggering user's own devices* — the
`emergency_contacts` table was read by nothing in the alert path.

The assertions below are mostly about honesty under partial failure. A
safety app that reports "3 contacts notified" when two messages bounced is
worse than one that reports the truth, because the user stops looking for
another way to get help.
"""

from __future__ import annotations

import os
import unittest
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
from fastapi_app.models import NotificationLog, User
from fastapi_app.services.emergency_dispatch import MAX_ATTEMPTS, dispatch_to_contacts
from fastapi_app.services.onesignal import (
    OneSignalDeliveryError,
    OneSignalEmailSender,
    build_emergency_email,
)
from fastapi_app.services.smtp_email import (
    SmtpEmailSender,
    build_email_sender,
    plain_text_fallback,
)
from fastapi_app.services.sms import (
    SMS_SEGMENT_LIMIT,
    SmsDeliveryError,
    build_emergency_sms,
    maps_link,
)


class FakeSmsSender:
    """Stands in for Twilio. `failures` names the numbers that should be
    refused, so a test can make one contact fail while others succeed.
    """

    def __init__(self, *, configured: bool = True, failures: set[str] | None = None):
        self.configured = configured
        self.failures = failures or set()
        self.sent: list[tuple[str, str]] = []
        self.attempts = 0

    @property
    def is_configured(self) -> bool:
        return self.configured

    async def send(self, *, to: str, body: str) -> str:
        self.attempts += 1
        if to in self.failures:
            raise SmsDeliveryError("Twilio rejected the message (HTTP 400).")
        self.sent.append((to, body))
        return f"SM{uuid4().hex[:8]}"


class FakeEmailSender:
    """Stands in for OneSignal."""

    def __init__(self, *, configured: bool = True, failures: set[str] | None = None):
        self.configured = configured
        self.failures = failures or set()
        self.sent: list[tuple[str, str, str]] = []
        self.attempts = 0

    @property
    def is_configured(self) -> bool:
        return self.configured

    async def send(self, *, to: str, subject: str, html_body: str) -> str:
        self.attempts += 1
        if to in self.failures:
            raise OneSignalDeliveryError("OneSignal rejected the message (HTTP 400).")
        self.sent.append((to, subject, html_body))
        return "notif-id"


class TestEmailComposition(unittest.TestCase):
    def test_subject_carries_the_whole_message(self):
        subject, _ = build_emergency_email(
            user_name="Priya Patel",
            contact_name="Anika",
            maps_url="https://maps.google.com/?q=1,2",
            local_time="14:05 UTC",
        )

        # A locked phone shows the subject and nothing else, so it has to
        # say who and that it is an emergency on its own.
        self.assertIn("EMERGENCY", subject)
        self.assertIn("Priya Patel", subject)

    def test_body_links_the_location(self):
        _, body = build_emergency_email(
            user_name="Priya",
            contact_name="Anika",
            maps_url="https://maps.google.com/?q=17.385,78.487",
            local_time="14:05 UTC",
        )

        self.assertIn("https://maps.google.com/?q=17.385,78.487", body)
        self.assertIn("Anika", body)

    def test_missing_location_says_so_rather_than_linking_nowhere(self):
        _, body = build_emergency_email(
            user_name="Priya", contact_name="Anika", maps_url=None, local_time="14:05 UTC"
        )

        self.assertIn("No location was available", body)
        self.assertNotIn("maps.google.com", body)

    def test_names_are_escaped(self):
        # A display name is user-controlled and lands in an HTML email.
        _, body = build_emergency_email(
            user_name="<script>alert(1)</script>",
            contact_name="Anika",
            maps_url=None,
            local_time="14:05 UTC",
        )

        self.assertNotIn("<script>", body)
        self.assertIn("&lt;script&gt;", body)


class TestEmailChannelSelection(unittest.TestCase):
    """Which email channel gets used, and why.

    OneSignal needs a sending domain you own with SPF/DKIM/DMARC records and
    refuses Gmail/Outlook as senders — so a project without a domain cannot
    use it at all. Plain SMTP through an ordinary mailbox needs neither, and
    is therefore preferred: not because it delivers better, but because it
    is the one that can actually be configured.
    """

    def _settings(self, **overrides) -> Settings:
        base = {
            "smtp_host": None,
            "smtp_from_email": None,
            "onesignal_app_id": None,
            "onesignal_api_key": None,
        }
        base.update(overrides)
        return Settings(**base)

    def test_smtp_wins_when_both_are_configured(self):
        settings = self._settings(
            smtp_host="smtp.gmail.com",
            smtp_from_email="alerts@example.com",
            onesignal_app_id="app",
            onesignal_api_key="key",
        )
        sender = build_email_sender(
            settings,
            onesignal_sender=OneSignalEmailSender(app_id="app", api_key="key"),
        )

        self.assertIsInstance(sender, SmtpEmailSender)

    def test_onesignal_is_used_when_smtp_is_absent(self):
        settings = self._settings(onesignal_app_id="app", onesignal_api_key="key")
        sender = build_email_sender(
            settings,
            onesignal_sender=OneSignalEmailSender(app_id="app", api_key="key"),
        )

        self.assertIsInstance(sender, OneSignalEmailSender)

    def test_neither_configured_reports_unconfigured_rather_than_crashing(self):
        sender = build_email_sender(self._settings(), onesignal_sender=None)

        self.assertIsNone(sender)

    def test_smtp_needs_both_host_and_from_address(self):
        half = self._settings(smtp_host="smtp.gmail.com")

        self.assertFalse(SmtpEmailSender(half).is_configured)


class TestSmtpTransportSelection(unittest.TestCase):
    """Which TLS style SMTP uses, and why it is inferred from the port.

    Port 465 speaks TLS from the first byte; 587 and 25 begin in the clear
    and upgrade with STARTTLS. Many consumer ISPs block 25 and 587 as an
    anti-spam measure while leaving 465 open — a deployment that only knows
    STARTTLS then times out with no useful error, which is exactly what
    happened on this project's own network.
    """

    def test_465_means_implicit_tls(self):
        self.assertTrue(Settings(smtp_port=465).smtp_use_ssl)

    def test_587_and_25_use_starttls(self):
        self.assertFalse(Settings(smtp_port=587).smtp_use_ssl)
        self.assertFalse(Settings(smtp_port=25).smtp_use_ssl)

    def test_an_explicit_override_wins_over_the_port(self):
        # A provider on a non-standard SMTPS port still has to be reachable.
        self.assertTrue(Settings(smtp_port=2465, smtp_use_ssl_override=True).smtp_use_ssl)
        self.assertFalse(Settings(smtp_port=465, smtp_use_ssl_override=False).smtp_use_ssl)


class TestPlainTextFallback(unittest.TestCase):
    def test_keeps_the_links_a_reader_must_act_on(self):
        _, html_body = build_emergency_email(
            user_name="Priya",
            contact_name="Anika",
            maps_url="https://maps.google.com/?q=17.385,78.487",
            local_time="14:05 UTC",
        )
        text = plain_text_fallback(subject="EMERGENCY: Priya needs help now", html_body=html_body)

        # A multipart/alternative with no usable text part loses the one
        # thing the reader needs on a client that refuses HTML.
        self.assertIn("https://maps.google.com/?q=17.385,78.487", text)
        self.assertIn("EMERGENCY", text)
        self.assertNotIn("<a href", text)


class TestSmsComposition(unittest.TestCase):
    """`build_emergency_sms` is pure, so it gets plain unit tests."""

    def test_message_names_the_user_and_carries_the_location(self):
        body = build_emergency_sms(
            user_name="Priya Patel",
            maps_url=maps_link(17.3850, 78.4867),
            local_time="14:05 UTC",
        )

        self.assertIn("Priya Patel", body)
        self.assertIn("SafeHer SOS", body)
        self.assertIn("17.385000,78.486700", body)
        self.assertIn("14:05 UTC", body)

    def test_message_fits_one_segment(self):
        body = build_emergency_sms(
            user_name="A" * 200,
            maps_url=maps_link(17.3850, 78.4867),
            local_time="14:05 UTC",
            evidence_url="https://evidence.safeherapp.com/" + "b" * 80,
        )

        # FR-EMG-05: "SMS < 160 chars with link".
        self.assertLessEqual(len(body), SMS_SEGMENT_LIMIT)

    def test_location_survives_truncation_at_the_expense_of_evidence(self):
        link = maps_link(17.3850, 78.4867)
        body = build_emergency_sms(
            user_name="A" * 120,
            maps_url=link,
            local_time="14:05 UTC",
            evidence_url="https://evidence.safeherapp.com/abcdefghijklmnop",
        )

        # Where someone is beats what was recorded, every time.
        self.assertIn(link, body)
        self.assertNotIn("evidence.safeherapp.com", body)

    def test_no_location_is_omitted_rather_than_faked(self):
        body = build_emergency_sms(user_name="Priya", maps_url=None, local_time="14:05 UTC")

        self.assertNotIn("maps.google.com", body)
        self.assertNotIn("0.000000", body)

    def test_maps_link_is_none_without_a_fix(self):
        self.assertIsNone(maps_link(None, None))
        self.assertIsNone(maps_link(17.385, None))


class TestEmergencyDispatch(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://testserver",
        )
        self.email = f"dispatch-{uuid4().hex}@safeherapp.com"
        self.headers = {"Authorization": f"Bearer {await self._login()}"}

    async def asyncTearDown(self):
        await self.client.aclose()

    async def _login(self) -> str:
        register = await self.client.post(
            "/api/v1/auth/register",
            json={
                "email": self.email,
                "password": "TestPass123!",
                "full_name": "Priya Patel",
                "role": "user",
            },
        )
        self.assertEqual(register.status_code, 201, register.text)
        login = await self.client.post(
            "/api/v1/auth/login", json={"email": self.email, "password": "TestPass123!"}
        )
        self.assertEqual(login.status_code, 200, login.text)
        return login.json()["access_token"]

    async def _add_contact(
        self, *, name: str, phone: str, priority: int = 1, email: str | None = None
    ) -> str:
        payload = {
            "name": name,
            "phone": phone,
            "relationship": "Sister",
            "priority": priority,
        }
        if email:
            payload["email"] = email
        response = await self.client.post(
            "/api/v1/users/me/emergency-contacts",
            headers=self.headers,
            json=payload,
        )
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()["id"]

    async def _current_user(self) -> User:
        async with SessionLocal() as session:
            return (
                (await session.execute(select(User).where(User.email == self.email)))
                .scalars()
                .one()
            )

    async def _dispatch(self, sender: FakeSmsSender, emailer=None, **kwargs) -> object:
        user = await self._current_user()
        async with SessionLocal() as session:
            return await dispatch_to_contacts(
                session=session,
                settings=Settings(),
                user=user,
                incident_id=kwargs.pop("incident_id", f"inc_{uuid4().hex[:8]}"),
                sms_sender=sender,
                email_sender=emailer or FakeEmailSender(configured=False),
                **kwargs,
            )

    # ------------------------------------------------------------- email

    async def test_a_contact_with_an_email_gets_one(self):
        await self._add_contact(name="Anika", phone="+911111111111", email="anika@example.com")

        emailer = FakeEmailSender()
        report = await self._dispatch(
            FakeSmsSender(configured=False), emailer=emailer, latitude=17.385, longitude=78.487
        )

        self.assertEqual(len(emailer.sent), 1)
        self.assertEqual(emailer.sent[0][0], "anika@example.com")
        # Email alone still counts as reaching the contact — it is a weaker
        # channel than SMS, but it is not nothing.
        self.assertEqual(report.contacts_notified, 1)

    async def test_a_contact_without_an_email_is_not_emailed(self):
        await self._add_contact(name="Anika", phone="+911111111111")

        emailer = FakeEmailSender()
        await self._dispatch(FakeSmsSender(configured=False), emailer=emailer)

        self.assertEqual(emailer.sent, [])

    async def test_email_and_sms_are_reported_separately(self):
        await self._add_contact(name="Anika", phone="+911111111111", email="anika@example.com")

        report = await self._dispatch(FakeSmsSender(), emailer=FakeEmailSender())

        self.assertEqual(
            sorted(report.results[0].delivered_channels), ["email", "sms"]
        )

    async def test_email_failure_does_not_hide_a_successful_sms(self):
        await self._add_contact(name="Anika", phone="+911111111111", email="anika@example.com")

        emailer = FakeEmailSender(failures={"anika@example.com"})
        report = await self._dispatch(FakeSmsSender(), emailer=emailer)

        self.assertEqual(report.contacts_notified, 1)
        self.assertIn("sms", report.results[0].delivered_channels)
        self.assertIn("email", report.results[0].failures)

    async def test_email_alone_reaches_a_contact_when_sms_is_unaffordable(self):
        # The configuration this project actually ships with: no Twilio
        # account, OneSignal's free email tier only.
        await self._add_contact(name="Anika", phone="+911111111111", email="anika@example.com")

        report = await self._dispatch(
            FakeSmsSender(configured=False), emailer=FakeEmailSender()
        )

        self.assertEqual(report.contacts_notified, 1)
        self.assertEqual(report.results[0].delivered_channels, ["email"])
        self.assertIn("not configured", report.results[0].failures["sms"])

    # ------------------------------------------------------- the happy path

    async def test_every_contact_is_messaged(self):
        await self._add_contact(name="Anika", phone="+911111111111", priority=1)
        await self._add_contact(name="Rahul", phone="+912222222222", priority=2)

        sender = FakeSmsSender()
        report = await self._dispatch(sender, latitude=17.3850, longitude=78.4867)

        self.assertEqual(report.contacts_total, 2)
        self.assertEqual(report.contacts_notified, 2)
        self.assertEqual({to for to, _ in sender.sent}, {"+911111111111", "+912222222222"})

    async def test_contacts_are_messaged_in_the_user_s_priority_order(self):
        await self._add_contact(name="Third", phone="+913333333333", priority=3)
        await self._add_contact(name="First", phone="+911111111111", priority=1)
        await self._add_contact(name="Second", phone="+912222222222", priority=2)

        sender = FakeSmsSender()
        await self._dispatch(sender, latitude=17.3850, longitude=78.4867)

        # Drag-to-reorder is a safety feature, not a preference: the person
        # most likely to help must be messaged first.
        self.assertEqual(
            [to for to, _ in sender.sent],
            ["+911111111111", "+912222222222", "+913333333333"],
        )

    async def test_the_message_carries_the_user_s_name_and_location(self):
        await self._add_contact(name="Anika", phone="+911111111111")

        sender = FakeSmsSender()
        await self._dispatch(sender, latitude=17.3850, longitude=78.4867)

        _, body = sender.sent[0]
        self.assertIn("Priya Patel", body)
        self.assertIn("maps.google.com", body)

    async def test_dispatch_without_a_location_still_reaches_contacts(self):
        await self._add_contact(name="Anika", phone="+911111111111")

        sender = FakeSmsSender()
        report = await self._dispatch(sender)

        # GPS may be off or refused. That must never be a reason to stay
        # silent about an emergency.
        self.assertEqual(report.contacts_notified, 1)
        self.assertNotIn("maps.google.com", sender.sent[0][1])

    # -------------------------------------------------------- partial failure

    async def test_one_bad_number_does_not_stop_the_others(self):
        await self._add_contact(name="Broken", phone="+919999999999", priority=1)
        await self._add_contact(name="Fine", phone="+911111111111", priority=2)

        sender = FakeSmsSender(failures={"+919999999999"})
        report = await self._dispatch(sender)

        self.assertEqual(report.contacts_total, 2)
        self.assertEqual(report.contacts_notified, 1)
        self.assertEqual([to for to, _ in sender.sent], ["+911111111111"])

    async def test_a_failed_contact_is_reported_as_failed(self):
        await self._add_contact(name="Broken", phone="+919999999999")

        sender = FakeSmsSender(failures={"+919999999999"})
        report = await self._dispatch(sender)

        # Reporting a bounce as success would stop a user looking for
        # another way to reach help.
        self.assertEqual(report.contacts_notified, 0)
        self.assertIn("sms", report.results[0].failures)

    async def test_delivery_is_retried_before_giving_up(self):
        await self._add_contact(name="Broken", phone="+919999999999")

        sender = FakeSmsSender(failures={"+919999999999"})
        await self._dispatch(sender)

        self.assertEqual(sender.attempts, MAX_ATTEMPTS)

    async def test_unconfigured_sms_is_reported_not_faked(self):
        await self._add_contact(name="Anika", phone="+911111111111")

        sender = FakeSmsSender(configured=False)
        report = await self._dispatch(sender)

        self.assertEqual(report.contacts_notified, 0)
        self.assertEqual(sender.attempts, 0)
        self.assertIn("not configured", report.results[0].failures["sms"])

    async def test_no_contacts_reports_zero_rather_than_erroring(self):
        sender = FakeSmsSender()
        report = await self._dispatch(sender)

        self.assertEqual(report.contacts_total, 0)
        self.assertEqual(report.contacts_notified, 0)

    # -------------------------------------------------------------- auditing

    async def test_every_attempt_is_logged_without_leaking_the_message(self):
        await self._add_contact(name="Anika", phone="+911111111111")
        incident_id = f"inc_{uuid4().hex[:8]}"

        sender = FakeSmsSender()
        await self._dispatch(sender, incident_id=incident_id, latitude=17.385, longitude=78.487)

        user = await self._current_user()
        async with SessionLocal() as session:
            logs = (
                (
                    await session.execute(
                        select(NotificationLog).where(NotificationLog.user_id == user.id)
                    )
                )
                .scalars()
                .all()
            )

        sms_logs = [row for row in logs if row.channel == "sms"]
        self.assertTrue(sms_logs)
        self.assertEqual(sms_logs[-1].status, "sent")
        self.assertIn(incident_id, sms_logs[-1].payload)
        # The body carries a live location and the row would carry a phone
        # number; neither belongs in a second store.
        self.assertNotIn("maps.google.com", sms_logs[-1].payload)
        self.assertNotIn("+911111111111", sms_logs[-1].payload)

    # ------------------------------------------------------ the HTTP contract

    # ------------------------------------------------------ channel report

    async def test_channels_endpoint_says_sms_is_unavailable(self):
        # The app cannot infer this: whether SMS works depends on server-side
        # credentials the client never sees. Without it, a phone-only contact
        # would show as ready in the UI and let a user believe her sister
        # will be called.
        response = await self.client.get("/api/v1/alerts/channels", headers=self.headers)

        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        self.assertFalse(body["sms"])
        self.assertIn("email", body)
        self.assertIn("push", body)

    async def test_email_requires_address_is_true_when_email_is_the_only_channel(self):
        response = await self.client.get("/api/v1/alerts/channels", headers=self.headers)
        body = response.json()

        # Exactly the state this deployment ships in, and the flag the
        # contacts screen keys its warning off.
        self.assertEqual(body["email_requires_address"], body["email"] and not body["sms"])

    async def test_channels_endpoint_requires_authentication(self):
        response = await self.client.get("/api/v1/alerts/channels")
        self.assertIn(response.status_code, (401, 403), response.text)

    async def test_the_sos_endpoint_reports_how_many_contacts_it_reached(self):
        await self._add_contact(name="Anika", phone="+911111111111")

        response = await self.client.post(
            "/api/v1/alerts/emergency",
            headers=self.headers,
            json={
                "severity": "critical",
                "summary": "SOS",
                "location": {"latitude": 17.3850, "longitude": 78.4867, "accuracy": 5.0},
            },
        )

        self.assertEqual(response.status_code, 201, response.text)
        body = response.json()
        self.assertEqual(body["contacts_total"], 1)
        # Twilio is unconfigured in CI, so nothing can actually be delivered
        # — and the endpoint says so instead of claiming a send.
        self.assertEqual(body["contacts_notified"], 0)

    async def test_the_sos_still_succeeds_when_dispatch_reaches_nobody(self):
        response = await self.client.post(
            "/api/v1/alerts/emergency",
            headers=self.headers,
            json={
                "severity": "high",
                "summary": "SOS",
                "location": {"latitude": 17.3850, "longitude": 78.4867},
            },
        )

        # The incident must be recorded regardless. Failing the request
        # would make the app believe the SOS never landed at all.
        self.assertEqual(response.status_code, 201, response.text)
        self.assertEqual(response.json()["contacts_total"], 0)

    async def test_listing_incidents_does_not_claim_a_dispatch_happened(self):
        await self.client.post(
            "/api/v1/alerts/emergency",
            headers=self.headers,
            json={"severity": "high", "summary": "SOS", "location": {"latitude": 1.0, "longitude": 2.0}},
        )

        response = await self.client.get("/api/v1/incidents/", headers=self.headers)
        self.assertEqual(response.status_code, 200, response.text)

        # None, not 0: no dispatch was attempted on this endpoint, which is
        # a different fact from "attempted and reached nobody".
        self.assertIsNone(response.json()[0]["contacts_notified"])


if __name__ == "__main__":
    unittest.main()
