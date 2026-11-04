"""Retraction of a false automatic alert — SRS FR-EMG-02.

Auto-SOS dispatches the instant fused confidence crosses the threshold, with
no cancellable countdown in front of it. That is a recorded decision, and the
reasoning holds: the situations auto-SOS exists for are the ones where she
cannot reach the screen, so a confirmation step would withhold the alert
exactly when it is needed.

The decision's cost is that a false automatic alarm was unrecoverable. It
reached her contacts and nothing she did afterwards told them otherwise. The
tests here cover the way back, and they are written around the two mistakes
that would make it worse than nothing:

* **The correction overtaking the alarm.** A retraction sent while the
  fan-out is still running would leave contacts further down the priority
  list holding "FALSE ALARM" and then "EMERGENCY". That ordering is worse
  than no retraction at all, so retracting has to *stop* the fan-out rather
  than race it.
* **Correcting the wrong people.** A contact who was never reached and gets
  a stand-down is confused; a contact who was reached and gets none may call
  the police. Those are not symmetric, so the rule is deliberately
  over-inclusive and asserted as such.

One test here is not about retraction at all. `test_a_contact_who_is_also_a_
safeher_user_does_not_abort_the_fanout` covers a `NameError` that lived in
the alarm path: `_notify_contact` called `fcm_credentials` without importing
it, so any contact who happened to have a SafeHer account of their own took
out the whole dispatch and every contact ranked below them. It is tested here
because the retraction fan-out copies that push block, and a fix for one has
to hold for both.
"""

from __future__ import annotations

import os
import unittest
from pathlib import Path
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]

os.environ["DATABASE_URL"] = "sqlite:///./test_safeher.db"
os.environ["ENABLE_MQTT_WORKER"] = "false"
os.environ["JWT_SECRET_KEY"] = "test-secret-key-change-me"
os.environ["LOG_LEVEL"] = "WARNING"

import httpx
from sqlalchemy import select

from fastapi_app.config import Settings
from fastapi_app.db import SessionLocal, init_db
from fastapi_app.main import app
from fastapi_app.models import FcmToken, Incident, NotificationLog, User
from fastapi_app.services import emergency_dispatch as dispatch
from fastapi_app.services.onesignal import (
    OneSignalDeliveryError,
    build_retraction_email,
)
from fastapi_app.services.sms import (
    SMS_SEGMENT_LIMIT,
    SmsDeliveryError,
    build_retraction_sms,
)


class FakeSmsSender:
    """Stands in for Twilio, recording what was sent to whom."""

    def __init__(self, *, configured: bool = True, failures: set[str] | None = None):
        self.configured = configured
        self.failures = failures or set()
        self.sent: list[tuple[str, str]] = []

    @property
    def is_configured(self) -> bool:
        return self.configured

    async def send(self, *, to: str, body: str) -> str:
        if to in self.failures:
            raise SmsDeliveryError("Twilio rejected the message (HTTP 400).")
        self.sent.append((to, body))
        return f"SM{uuid4().hex[:8]}"

    @property
    def recipients(self) -> list[str]:
        return [to for to, _ in self.sent]


class FakeEmailSender:
    def __init__(self, *, configured: bool = True, failures: set[str] | None = None):
        self.configured = configured
        self.failures = failures or set()
        self.sent: list[tuple[str, str, str]] = []

    @property
    def is_configured(self) -> bool:
        return self.configured

    async def send(self, *, to: str, subject: str, html_body: str) -> str:
        if to in self.failures:
            raise OneSignalDeliveryError("OneSignal rejected the message (HTTP 400).")
        self.sent.append((to, subject, html_body))
        return "notif-id"

    @property
    def recipients(self) -> list[str]:
        return [to for to, _, _ in self.sent]


# --------------------------------------------------------------- message bodies


class TestRetractionMessages(unittest.TestCase):
    def test_the_sms_leads_with_the_correction(self):
        body = build_retraction_sms(user_name="Priya Patel", local_time="14:05 UTC")

        # This may land on a lock screen directly beneath the alarm. A reader
        # skimming two SafeHer texts has to be able to tell which is current
        # from the first few words alone.
        self.assertTrue(body.startswith("SafeHer: FALSE ALARM"), body)
        self.assertIn("Priya Patel", body)
        self.assertIn("safe", body.lower())

    def test_the_sms_never_reads_as_a_second_emergency(self):
        body = build_retraction_sms(user_name="Priya", local_time="14:05 UTC")

        # "SOS" and "needs help" are the alarm's words. A correction that
        # contains them is one a panicking reader can misread as another alert.
        self.assertNotIn("SOS", body)
        self.assertNotIn("needs help", body)

    def test_the_sms_fits_one_segment(self):
        body = build_retraction_sms(user_name="Priya Patel", local_time="14:05 UTC")

        self.assertLessEqual(len(body), SMS_SEGMENT_LIMIT)

    def test_a_long_name_is_trimmed_rather_than_the_meaning(self):
        body = build_retraction_sms(user_name="A" * 300, local_time="14:05 UTC")

        self.assertLessEqual(len(body), SMS_SEGMENT_LIMIT)
        # The three load-bearing clauses survive: that it is false, and that
        # nobody needs to act. Losing either to a long display name would
        # turn the correction into noise.
        self.assertIn("FALSE ALARM", body)

    def test_the_email_subject_carries_the_whole_message(self):
        subject, _ = build_retraction_email(
            user_name="Priya Patel", contact_name="Anika", local_time="14:05 UTC"
        )

        self.assertIn("FALSE ALARM", subject)
        self.assertIn("Priya Patel", subject)
        self.assertIn("safe", subject.lower())

    def test_the_email_does_not_link_anywhere(self):
        _, body = build_retraction_email(
            user_name="Priya", contact_name="Anika", local_time="14:05 UTC"
        )

        # This message exists to stand the alarm down. A location link or an
        # evidence link invites the reader to go looking, which works against
        # the only thing it is for.
        self.assertNotIn("maps.google.com", body)
        self.assertNotIn("href", body)

    def test_names_are_escaped(self):
        _, body = build_retraction_email(
            user_name="<script>alert(1)</script>",
            contact_name="Anika",
            local_time="14:05 UTC",
        )

        self.assertNotIn("<script>", body)
        self.assertIn("&lt;script&gt;", body)


class TestRetractionWindowIsAPromptNotADeadline(unittest.TestCase):
    """The 60 seconds is how long the app *offers* the action.

    Nothing server-side refuses a later retraction, and that asymmetry is
    deliberate: a deadline's only effect would be to withhold a correction she
    has decided to send. This pins the constant so that if someone later turns
    it into an enforced window, they have to come through here.
    """

    def test_the_prompt_duration_is_sixty_seconds(self):
        self.assertEqual(dispatch.RETRACTION_PROMPT_SECONDS, 60)

    def test_the_app_offers_the_action_for_exactly_that_long(self):
        """The Dart constant and this one are a pair.

        The app decides how long the stand-down banner stays up; the server
        decides nothing about it. If the two drift, the banner either vanishes
        while the window is open or lingers claiming an action it believes is
        still offered. Nothing in either language would notice, so it is
        pinned from here — the same way the deployed scorer constants are.
        """
        import re

        source = (
            ROOT / "mobile/lib/features/safety/data/auto_sos_retraction.dart"
        ).read_text(encoding="utf-8")
        match = re.search(
            r"kAutoSosRetractionPrompt = Duration\(seconds: (\d+)\)", source
        )
        self.assertIsNotNone(match, "the Dart prompt constant has moved or been renamed")
        self.assertEqual(int(match.group(1)), dispatch.RETRACTION_PROMPT_SECONDS)

    def test_no_deadline_is_enforced_anywhere(self):
        import inspect

        from fastapi_app.routers import alerts

        router_source = inspect.getsource(alerts.retract_emergency)
        service_source = inspect.getsource(dispatch.retract_to_contacts)

        # If either of these starts comparing the constant against a clock,
        # the window has stopped being a prompt and this test should fail so
        # the change is a deliberate one.
        for source in (router_source, service_source):
            self.assertNotIn("RETRACTION_PROMPT_SECONDS", source)


# ------------------------------------------------------------------ integration


class RetractionTestCase(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://testserver",
        )
        self.email = f"retract-{uuid4().hex}@safeherapp.com"
        self.token = await self._register(self.email)
        self.headers = {"Authorization": f"Bearer {self.token}"}

    async def asyncTearDown(self):
        await self.client.aclose()

    async def _register(self, email: str) -> str:
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

    async def _add_contact(
        self,
        *,
        name: str,
        phone: str,
        priority: int = 1,
        email: str | None = None,
        headers: dict | None = None,
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
            headers=headers or self.headers,
            json=payload,
        )
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()["id"]

    async def _owner(self, email: str | None = None) -> User:
        async with SessionLocal() as session:
            return (
                (await session.execute(select(User).where(User.email == (email or self.email))))
                .scalars()
                .one()
            )

    async def _create_incident(self, *, auto: bool = True) -> str:
        """An incident owned by this user, created through the real endpoint."""
        response = await self.client.post(
            "/api/v1/alerts/emergency",
            headers=self.headers,
            json={
                "auto": auto,
                "severity": "high",
                "summary": "Automatic: fused confidence crossed the threshold",
                "location": {"lat": 17.385, "lng": 78.487},
            },
        )
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()["id"]

    async def _incident(self, incident_id: str) -> Incident:
        async with SessionLocal() as session:
            return await session.get(Incident, incident_id)


class TestTheFanoutSurvivesAContactWhoIsAUser(RetractionTestCase):
    """A pre-existing crash in the *alarm* path, not the retraction one.

    `_notify_contact` reached for `fcm_credentials` without importing it. The
    name only resolves when a contact also has a SafeHer account with a
    registered device, which no test had -- so the push branch was never
    executed and the `NameError` sat there. When it did fire it escaped
    `dispatch_to_contacts` entirely, which meant the contact who triggered it
    *and every contact ranked below them* were never notified.
    """

    async def test_a_contact_who_is_also_a_safeher_user_does_not_abort_the_fanout(self):
        # Contact 1 is herself a SafeHer user with a device token, which is
        # what lights up the push branch.
        peer_email = f"peer-{uuid4().hex}@safeherapp.com"
        await self._register(peer_email)
        peer = await self._owner(peer_email)
        peer_phone = "+919000000001"
        async with SessionLocal() as session:
            peer_row = await session.get(User, peer.id)
            peer_row.phone = peer_phone
            session.add(FcmToken(user_id=peer.id, token=f"tok-{uuid4().hex}"))
            await session.commit()

        await self._add_contact(name="Peer", phone=peer_phone, priority=1)
        await self._add_contact(name="Anika", phone="+919000000002", priority=2)

        sender = FakeSmsSender()
        owner = await self._owner()
        async with SessionLocal() as session:
            report = await dispatch.dispatch_to_contacts(
                session=session,
                settings=Settings(),
                user=owner,
                incident_id=f"inc_{uuid4().hex[:8]}",
                sms_sender=sender,
                email_sender=FakeEmailSender(configured=False),
            )

        # The assertion that matters is the second contact. Before the fix the
        # fan-out raised at the first one and Anika was never tried at all.
        self.assertEqual(len(report.results), 2, report.as_dict())
        self.assertIn("+919000000002", sender.recipients)
        self.assertEqual(report.contacts_notified, 2, report.as_dict())


class TestRetractionReachesTheRightPeople(RetractionTestCase):
    async def test_the_correction_goes_to_the_contacts_the_alarm_reached(self):
        incident_id = await self._create_incident()
        reached = await self._add_contact(
            name="Anika", phone="+919111111111", email="anika@example.com", priority=1
        )
        missed = await self._add_contact(
            name="Meera", phone="+919222222222", email="meera@example.com", priority=2
        )

        # Alarm: Anika's SMS lands, Meera's is refused on every channel.
        alarm_sms = FakeSmsSender(failures={"+919222222222"})
        alarm_email = FakeEmailSender(failures={"meera@example.com"})
        owner = await self._owner()
        async with SessionLocal() as session:
            alarm = await dispatch.dispatch_to_contacts(
                session=session,
                settings=Settings(),
                user=owner,
                incident_id=incident_id,
                sms_sender=alarm_sms,
                email_sender=alarm_email,
            )
        self.assertEqual(alarm.reached_contact_ids, [reached])
        self.assertEqual(alarm.failed_contact_ids, [missed])

        # Retraction: only the contact who was actually told.
        retract_sms = FakeSmsSender()
        retract_email = FakeEmailSender()
        async with SessionLocal() as session:
            incident = await session.get(Incident, incident_id)
            contact_ids = await dispatch.reached_contacts_for_incident(
                session, incident_id=incident_id, incident=incident
            )
            report = await dispatch.retract_to_contacts(
                session=session,
                settings=Settings(),
                user=owner,
                incident_id=incident_id,
                contact_ids=contact_ids,
                sms_sender=retract_sms,
                email_sender=retract_email,
            )

        self.assertEqual(contact_ids, [reached])
        self.assertEqual(retract_sms.recipients, ["+919111111111"])
        self.assertEqual(report.contacts_notified, 1, report.as_dict())
        # Meera was never alarmed, so she must not be told a false alarm she
        # could not have received.
        self.assertNotIn("+919222222222", retract_sms.recipients)
        self.assertNotIn("meera@example.com", retract_email.recipients)

    async def test_the_correction_uses_sms_and_not_only_email(self):
        """`send_evidence_followup` is email-only on cost grounds. This is not.

        A contact holding a text that says someone is in danger has to be
        corrected on the channel they are holding.
        """
        incident_id = await self._create_incident()
        contact = await self._add_contact(
            name="Anika", phone="+919111111111", email="anika@example.com"
        )

        retract_sms = FakeSmsSender()
        retract_email = FakeEmailSender()
        owner = await self._owner()
        async with SessionLocal() as session:
            report = await dispatch.retract_to_contacts(
                session=session,
                settings=Settings(),
                user=owner,
                incident_id=incident_id,
                contact_ids=[contact],
                sms_sender=retract_sms,
                email_sender=retract_email,
            )

        self.assertEqual(retract_sms.recipients, ["+919111111111"])
        self.assertEqual(retract_email.recipients, ["anika@example.com"])
        self.assertEqual(
            sorted(report.results[0].delivered_channels), ["email", "sms"]
        )

    async def test_a_contact_reached_only_by_push_is_still_corrected(self):
        """The notification log does not record push, so the union matters.

        `_notify_contact` logs SMS and email but not push, so a contact who
        was reached by push alone leaves no "sent" row. If the retraction read
        the log only, that contact would keep an emergency notification that
        nothing ever took back.
        """
        incident_id = await self._create_incident()
        contact = await self._add_contact(name="Anika", phone="+919111111111")

        # Stand in for a completed fan-out that reached her by push: the log
        # has no "sent" row, but the incident's own column names her.
        async with SessionLocal() as session:
            incident = await session.get(Incident, incident_id)
            incident.contacts_reached = f'["{contact}"]'
            await session.commit()

        async with SessionLocal() as session:
            incident = await session.get(Incident, incident_id)
            logged = await dispatch.reached_contacts_for_incident(
                session, incident_id=incident_id, incident=None
            )
            unioned = await dispatch.reached_contacts_for_incident(
                session, incident_id=incident_id, incident=incident
            )

        self.assertEqual(logged, [])
        self.assertEqual(unioned, [contact])

    async def test_a_wildcard_in_an_incident_id_does_not_pull_in_another_alert(self):
        """Incident ids are chosen by the client, so they can contain `_`.

        `_` is a single-character wildcard in SQL LIKE. Matching the audit log
        with a raw pattern meant retracting one alert could sweep in the log
        rows of another of her incidents — and send a false-alarm message to
        the contacts of an alert that was still live.
        """
        contact = await self._add_contact(name="Anika", phone="+919111111111")
        owner = await self._owner()

        # Two ids differing only where the wildcard would match. The stem is
        # fresh per run: `test_safeher.db` is a file shared by the whole suite
        # and not dropped between runs, so fixed ids accumulated audit rows
        # from every previous run's user and the assertions below drifted.
        stem = uuid4().hex[:12]
        live_id = f"inc{stem}X"
        wildcard_id = f"inc{stem}_"

        async with SessionLocal() as session:
            # The *live* alert reached her. Nothing has retracted it.
            await dispatch.dispatch_to_contacts(
                session=session,
                settings=Settings(),
                user=owner,
                incident_id=live_id,
                sms_sender=FakeSmsSender(),
                email_sender=FakeEmailSender(configured=False),
            )

        async with SessionLocal() as session:
            swept = await dispatch.reached_contacts_for_incident(
                session, incident_id=wildcard_id, incident=None
            )

        # The wildcard id reached nobody, so retracting it must correct nobody.
        self.assertEqual(swept, [], "a LIKE wildcard matched another incident's log rows")

        # And the real id still resolves correctly.
        async with SessionLocal() as session:
            self.assertEqual(
                await dispatch.reached_contacts_for_incident(
                    session, incident_id=live_id, incident=None
                ),
                [contact],
            )

    async def test_a_malformed_reached_column_does_not_break_the_retraction(self):
        incident_id = await self._create_incident()
        async with SessionLocal() as session:
            incident = await session.get(Incident, incident_id)
            incident.contacts_reached = "not json at all"
            await session.commit()

        async with SessionLocal() as session:
            incident = await session.get(Incident, incident_id)
            # A corrupt audit column must not turn standing down a false
            # alarm into a 500.
            self.assertEqual(
                await dispatch.reached_contacts_for_incident(
                    session, incident_id=incident_id, incident=incident
                ),
                [],
            )


class TestRetractionStopsTheAlarm(RetractionTestCase):
    async def test_retracting_mid_fanout_stops_the_remaining_contacts(self):
        """The correction must not overtake the alarm.

        Three contacts, and the incident is retracted after the first one is
        messaged. Contacts two and three must never be alarmed -- if they are,
        they receive "FALSE ALARM" and then "EMERGENCY", which is worse than
        no retraction at all.
        """
        incident_id = await self._create_incident()
        await self._add_contact(name="One", phone="+919111111111", priority=1)
        await self._add_contact(name="Two", phone="+919222222222", priority=2)
        await self._add_contact(name="Three", phone="+919333333333", priority=3)

        sender = FakeSmsSender()
        calls = {"n": 0}

        async def should_continue() -> bool:
            # Allow the first contact, then behave as the real predicate does
            # once `retracted_at` is set.
            calls["n"] += 1
            return calls["n"] <= 1

        owner = await self._owner()
        async with SessionLocal() as session:
            report = await dispatch.dispatch_to_contacts(
                session=session,
                settings=Settings(),
                user=owner,
                incident_id=incident_id,
                sms_sender=sender,
                email_sender=FakeEmailSender(configured=False),
                should_continue=should_continue,
            )

        self.assertEqual(sender.recipients, ["+919111111111"])
        self.assertEqual(len(report.results), 1, report.as_dict())

    async def test_the_real_predicate_reads_the_retracted_column(self):
        """`run_dispatch_in_background` must see a retraction committed by
        another session, which is why it probes on a session of its own."""
        incident_id = await self._create_incident()

        async def not_retracted() -> bool:
            async with SessionLocal() as probe:
                row = await probe.get(Incident, incident_id)
                return row is None or row.retracted_at is None

        self.assertTrue(await not_retracted())

        response = await self.client.post(
            f"/api/v1/alerts/emergency/{incident_id}/retract", headers=self.headers
        )
        self.assertEqual(response.status_code, 202, response.text)

        self.assertFalse(await not_retracted())


class TestRetractEndpoint(RetractionTestCase):
    async def test_retracting_records_it_and_reports_the_state(self):
        incident_id = await self._create_incident()

        response = await self.client.post(
            f"/api/v1/alerts/emergency/{incident_id}/retract", headers=self.headers
        )

        self.assertEqual(response.status_code, 202, response.text)
        body = response.json()
        self.assertEqual(body["incident_id"], incident_id)
        self.assertIsNotNone(body["retracted_at"])
        self.assertFalse(body["already_retracted"])

        incident = await self._incident(incident_id)
        self.assertIsNotNone(incident.retracted_at)

    async def test_retracting_twice_does_not_send_a_second_stand_down(self):
        """A double tap, or a retry on a flaky connection, must not tell every
        contact twice."""
        incident_id = await self._create_incident()

        first = await self.client.post(
            f"/api/v1/alerts/emergency/{incident_id}/retract", headers=self.headers
        )
        second = await self.client.post(
            f"/api/v1/alerts/emergency/{incident_id}/retract", headers=self.headers
        )

        self.assertEqual(first.status_code, 202, first.text)
        self.assertEqual(second.status_code, 202, second.text)
        self.assertFalse(first.json()["already_retracted"])
        self.assertTrue(second.json()["already_retracted"])
        # The timestamp is the first call's, not refreshed by the second.
        self.assertEqual(first.json()["retracted_at"], second.json()["retracted_at"])

    async def test_someone_elses_incident_is_not_found(self):
        incident_id = await self._create_incident()
        intruder = await self._register(f"intruder-{uuid4().hex}@safeherapp.com")

        response = await self.client.post(
            f"/api/v1/alerts/emergency/{incident_id}/retract",
            headers={"Authorization": f"Bearer {intruder}"},
        )

        # 404 rather than 403: an incident id must not be confirmed to exist
        # to someone who does not own it.
        self.assertEqual(response.status_code, 404, response.text)
        incident = await self._incident(incident_id)
        self.assertIsNone(incident.retracted_at)

    async def test_an_unknown_incident_is_not_found(self):
        response = await self.client.post(
            f"/api/v1/alerts/emergency/inc_{uuid4().hex}/retract", headers=self.headers
        )

        self.assertEqual(response.status_code, 404, response.text)

    async def test_retraction_requires_authentication(self):
        incident_id = await self._create_incident()

        response = await self.client.post(
            f"/api/v1/alerts/emergency/{incident_id}/retract"
        )

        self.assertIn(response.status_code, (401, 403), response.text)

    async def test_the_retraction_shows_up_on_the_incident_itself(self):
        """Not just on the retract response.

        The history screen reads incidents, and a corrected false alarm that
        still renders as an emergency makes her re-read an alert she already
        took back.
        """
        incident_id = await self._create_incident()
        await self.client.post(
            f"/api/v1/alerts/emergency/{incident_id}/retract", headers=self.headers
        )

        fetched = await self.client.get(
            f"/api/v1/incidents/{incident_id}", headers=self.headers
        )
        self.assertEqual(fetched.status_code, 200, fetched.text)
        self.assertIsNotNone(fetched.json()["retracted_at"])

        listing = await self.client.get("/api/v1/incidents/", headers=self.headers)
        self.assertEqual(listing.status_code, 200, listing.text)
        rows = listing.json()
        rows = rows["items"] if isinstance(rows, dict) else rows
        mine = [row for row in rows if row["id"] == incident_id]
        self.assertEqual(len(mine), 1, rows)
        self.assertIsNotNone(mine[0]["retracted_at"])

    async def test_a_real_emergency_is_not_marked_retracted(self):
        """The column's normal state is NULL, and it must never be rendered as
        "not yet retracted"."""
        incident_id = await self._create_incident()

        incident = await self._incident(incident_id)
        self.assertIsNone(incident.retracted_at)
        self.assertIsNone(incident.retraction_status)


class TestRetractionAuditTrail(RetractionTestCase):
    async def test_the_stand_down_is_logged_distinctly_from_the_alarm(self):
        """An operator reading the notification log has to be able to tell a
        correction from an alert."""
        incident_id = await self._create_incident()
        contact = await self._add_contact(name="Anika", phone="+919111111111")

        owner = await self._owner()
        async with SessionLocal() as session:
            await dispatch.retract_to_contacts(
                session=session,
                settings=Settings(),
                user=owner,
                incident_id=incident_id,
                contact_ids=[contact],
                sms_sender=FakeSmsSender(),
                email_sender=FakeEmailSender(configured=False),
            )

        async with SessionLocal() as session:
            rows = (
                (
                    await session.execute(
                        select(NotificationLog).where(
                            NotificationLog.payload.like(f"incident={incident_id}%")
                        )
                    )
                )
                .scalars()
                .all()
            )

        statuses = {row.status for row in rows}
        self.assertIn("retraction_sent", statuses)
        # And it must not be counted as an alarm delivery, or
        # `reached_contacts_for_incident` would treat a correction as evidence
        # that the alarm got through.
        self.assertNotIn("sent", statuses)

    async def test_a_retraction_sent_row_is_not_read_back_as_a_reach(self):
        incident_id = await self._create_incident()
        contact = await self._add_contact(name="Anika", phone="+919111111111")

        owner = await self._owner()
        async with SessionLocal() as session:
            await dispatch.retract_to_contacts(
                session=session,
                settings=Settings(),
                user=owner,
                incident_id=incident_id,
                contact_ids=[contact],
                sms_sender=FakeSmsSender(),
                email_sender=FakeEmailSender(configured=False),
            )

        async with SessionLocal() as session:
            self.assertEqual(
                await dispatch.reached_contacts_for_incident(
                    session, incident_id=incident_id, incident=None
                ),
                [],
            )


if __name__ == "__main__":
    unittest.main()
