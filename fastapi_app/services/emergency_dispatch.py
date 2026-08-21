"""Fan-out of an emergency alert to a user's emergency contacts.

This closes FR-EMG-04 and FR-EMG-05. Until now `POST /alerts/emergency`
created an incident, stored the location and pushed FCM to the *triggering
user's own devices* — it never read `emergency_contacts` at all, so the one
thing the product exists to do did not happen.

Design notes that are load-bearing:

* **Priority order.** Contacts are notified in the order the user ranked
  them (FR-EMG-10's drag-to-reorder is not decoration), so the person most
  likely to help is messaged first.
* **Per-contact isolation.** One bad phone number must never stop the rest
  of the fan-out. Every contact is attempted independently and its outcome
  recorded.
* **Retries.** FR-EMG-04 asks for three attempts. Backoff is deliberately
  short — the requirement also caps the whole dispatch at five seconds, and
  a polite exponential backoff would blow that budget while someone waits.
* **Honest accounting.** `contacts_notified` counts contacts that a channel
  actually accepted. A contact whose SMS failed and who has no app install
  is reported as failed, never quietly folded into the success count.
"""

from __future__ import annotations

import asyncio
import json
import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional, Sequence

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.config import Settings
from fastapi_app.models import EmergencyContact, FcmToken, NotificationLog, User
from fastapi_app.repositories import emergency_contacts as contacts_repo
from fastapi_app.services.notifications import send_fcm_notification
from fastapi_app.services.email import EmailDeliveryError, EmailNotConfigured
from fastapi_app.services.onesignal import (
    OneSignalDeliveryError,
    OneSignalEmailSender,
    OneSignalNotConfigured,
    build_emergency_email,
)
from fastapi_app.services.smtp_email import build_email_sender
from fastapi_app.services.sms import (
    SmsDeliveryError,
    SmsNotConfigured,
    SmsSender,
    build_emergency_sms,
    maps_link,
)

logger = logging.getLogger(__name__)

MAX_ATTEMPTS = 3
RETRY_DELAY_SECONDS = 0.5


@dataclass
class ContactDispatchResult:
    contact_id: str
    contact_name: str

    # Channels that accepted the message for this contact.
    delivered_channels: list[str] = field(default_factory=list)

    # Channels that were tried and refused, as `channel: reason`.
    failures: dict[str, str] = field(default_factory=dict)

    @property
    def notified(self) -> bool:
        return bool(self.delivered_channels)


@dataclass
class DispatchReport:
    results: list[ContactDispatchResult] = field(default_factory=list)

    @property
    def contacts_total(self) -> int:
        return len(self.results)

    @property
    def contacts_notified(self) -> int:
        return sum(1 for result in self.results if result.notified)

    @property
    def reached_contact_ids(self) -> list[str]:
        return [result.contact_id for result in self.results if result.notified]

    @property
    def failed_contact_ids(self) -> list[str]:
        """Contacts every channel refused.

        Kept apart from "not in `reached`" because the client renders the two
        differently: a contact still being attempted and a contact nobody
        could reach look identical in an aggregate count, and on this screen
        that difference is the whole message.
        """
        return [result.contact_id for result in self.results if not result.notified]

    def as_dict(self) -> dict:
        return {
            "contacts_total": self.contacts_total,
            "contacts_notified": self.contacts_notified,
            "contacts": [
                {
                    "contact_id": result.contact_id,
                    "name": result.contact_name,
                    "delivered": result.delivered_channels,
                    "failed": result.failures,
                }
                for result in self.results
            ],
        }


async def dispatch_to_contacts(
    *,
    session: AsyncSession,
    settings: Settings,
    user: User,
    incident_id: str,
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
    evidence_url: Optional[str] = None,
    sms_sender: Optional[SmsSender] = None,
    email_sender: Optional[OneSignalEmailSender] = None,
) -> DispatchReport:
    """Notifies every emergency contact. Never raises — a partial failure is
    reported, not thrown, because the incident is already recorded and the
    caller must still return a response to someone in danger.
    """
    contacts = await contacts_repo.list_by_user(session, user_id=user.id)
    report = DispatchReport()
    if not contacts:
        return report

    sender = sms_sender or SmsSender(
        account_sid=settings.twilio_account_sid,
        auth_token=settings.twilio_auth_token,
        from_number=settings.twilio_from_number,
    )
    # SMTP first, then OneSignal — see `smtp_email.build_email_sender` for
    # why. Either way the dispatcher only sees `is_configured` and `send`.
    emailer = email_sender or build_email_sender(
        settings,
        onesignal_sender=OneSignalEmailSender(
            app_id=settings.onesignal_app_id,
            api_key=settings.onesignal_api_key,
        ),
    )

    display_name = (user.full_name or user.email or "A SafeHer user").strip()
    link = maps_link(latitude, longitude)
    local_time = datetime.now(timezone.utc).strftime("%H:%M UTC")
    body = build_emergency_sms(
        user_name=display_name,
        maps_url=link,
        local_time=local_time,
        evidence_url=evidence_url,
    )

    # `list_by_user` already orders by priority, so this loop is the user's
    # own ranking.
    for contact in contacts:
        result = await _notify_contact(
            session=session,
            settings=settings,
            sender=sender,
            emailer=emailer,
            contact=contact,
            owner=user,
            incident_id=incident_id,
            body=body,
            maps_url=link,
            display_name=display_name,
            local_time=local_time,
            evidence_url=evidence_url,
        )
        report.results.append(result)

    return report


# --------------------------------------------------------------- background run

# The dispatch state machine, stored on `incidents.dispatch_status`.
DISPATCH_IN_PROGRESS = "in_progress"
DISPATCH_COMPLETE = "complete"
DISPATCH_FAILED = "failed"


async def run_dispatch_in_background(
    *,
    settings: Settings,
    user_id: str,
    incident_id: str,
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
    evidence_url: Optional[str] = None,
) -> None:
    """Fans the alert out after the response has already gone.

    Owns its own session deliberately. A FastAPI background task runs *after*
    the request completes, by which time the request-scoped `AsyncSession` the
    router held has been closed and returned to the pool -- using it here
    would fail on the first statement, and it would fail inside a task whose
    exceptions nobody is waiting on.

    Never raises. There is no caller left to catch anything: the client has
    its 201 and is polling for the outcome, so a crash here would present as
    a dispatch that stays `in_progress` forever. Every failure is recorded on
    the incident instead, where the client will read it.
    """
    # Imported here rather than at module scope: `db` imports `config`, which
    # imports this module's neighbours, and a top-level import closes that
    # loop at startup.
    from fastapi_app.db import SessionLocal
    from fastapi_app.models import Incident
    from fastapi_app.realtime import manager

    try:
        async with SessionLocal() as session:
            user = await session.get(User, user_id)
            if user is None:
                logger.error("Dispatch for incident %s: user %s is gone", incident_id, user_id)
                return

            report = await dispatch_to_contacts(
                session=session,
                settings=settings,
                user=user,
                incident_id=incident_id,
                latitude=latitude,
                longitude=longitude,
                evidence_url=evidence_url,
            )

            incident = await session.get(Incident, incident_id)
            if incident is not None:
                incident.dispatch_status = DISPATCH_COMPLETE
                incident.contacts_total = report.contacts_total
                incident.contacts_notified = report.contacts_notified
                incident.contacts_reached = json.dumps(report.reached_contact_ids)
                incident.contacts_failed = json.dumps(report.failed_contact_ids)
                incident.dispatch_completed_at = datetime.now(timezone.utc).replace(tzinfo=None)
                await session.commit()

            # Push the outcome as well as storing it.
            #
            # The stored row is the authority and the Emergency screen reads
            # it by polling, because a poll works whether or not a socket
            # happens to be open. This broadcast is for any client that is
            # already listening -- it saves a poll interval, and it is not
            # relied upon by anything.
            await manager.broadcast_to_user(
                user_id,
                {
                    "type": "dispatch_complete",
                    "incident_id": incident_id,
                    "contacts_total": report.contacts_total,
                    "contacts_notified": report.contacts_notified,
                    "contacts_reached": report.reached_contact_ids,
                    "contacts_failed": report.failed_contact_ids,
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                },
            )
    except Exception as exc:  # noqa: BLE001 - see docstring
        logger.exception("Emergency dispatch for incident %s failed: %s", incident_id, exc)
        try:
            async with SessionLocal() as session:
                incident = await session.get(Incident, incident_id)
                if incident is not None:
                    incident.dispatch_status = DISPATCH_FAILED
                    incident.dispatch_completed_at = datetime.now(timezone.utc).replace(
                        tzinfo=None
                    )
                    await session.commit()
        except Exception:  # noqa: BLE001
            # The status column is a convenience for the client, not the
            # record of the emergency -- the incident itself is already
            # committed. Losing this write must not mask the error above.
            logger.exception("Could not record dispatch failure for %s", incident_id)


async def _notify_contact(
    *,
    session: AsyncSession,
    settings: Settings,
    sender: SmsSender,
    emailer: OneSignalEmailSender,
    contact: EmergencyContact,
    owner: User,
    incident_id: str,
    body: str,
    maps_url: Optional[str],
    display_name: str,
    local_time: str,
    evidence_url: Optional[str],
) -> ContactDispatchResult:
    result = ContactDispatchResult(contact_id=contact.id, contact_name=contact.name)

    # --- SMS: reaches a contact who has never installed SafeHer -----------
    if sender.is_configured:
        error = await _with_retries(lambda: sender.send(to=contact.phone, body=body))
        if error is None:
            result.delivered_channels.append("sms")
            await _log(session, owner.id, "sms", "sent", incident_id, contact.id)
        else:
            result.failures["sms"] = error
            await _log(session, owner.id, "sms", "failed", incident_id, contact.id, reason=error)
    else:
        # Recorded rather than silently skipped: an operator reading the
        # notification log needs to see that the channel was unavailable,
        # not infer it from an absence.
        result.failures["sms"] = "Twilio is not configured"
        await _log(session, owner.id, "sms", "skipped_not_configured", incident_id, contact.id)

    # --- Email: free, and the only channel this project can rely on -------
    # Ranked below SMS on purpose. Nobody watches an inbox the way they
    # notice a text, so email is an additional channel rather than a
    # substitute — but it costs nothing, which makes it the one that works
    # when there is no budget for SMS at all.
    if contact.email:
        if emailer is not None and emailer.is_configured:
            subject, html_body = build_emergency_email(
                user_name=display_name,
                contact_name=contact.name,
                maps_url=maps_url,
                local_time=local_time,
                evidence_url=evidence_url,
            )
            error = await _with_retries(
                lambda: emailer.send(to=contact.email, subject=subject, html_body=html_body)
            )
            if error is None:
                result.delivered_channels.append("email")
                await _log(session, owner.id, "email", "sent", incident_id, contact.id)
            else:
                result.failures["email"] = error
                await _log(session, owner.id, "email", "failed", incident_id, contact.id, reason=error)
        else:
            result.failures["email"] = "No email channel is configured"
            await _log(
                session, owner.id, "email", "skipped_not_configured", incident_id, contact.id
            )

    # --- Push: only if this contact is themselves a SafeHer user ----------
    tokens = await _tokens_for_contact(session, contact)
    if tokens and fcm_credentials(settings).is_configured:
        delivered = False
        for token in tokens:
            error = await _with_retries(
                lambda token=token: send_fcm_notification(
                    credentials=fcm_credentials(settings),
                    token=token.token,
                    title="SafeHer emergency",
                    body=body,
                    data={
                        "incident_id": incident_id,
                        "type": "emergency_contact_alert",
                        "from_user_id": owner.id,
                        "maps_url": maps_url or "",
                    },
                    session=session,
                    user_id=token.user_id,
                    device_id=token.device_id,
                )
            )
            if error is None:
                delivered = True
        if delivered:
            result.delivered_channels.append("push")
        else:
            result.failures["push"] = "No device accepted the notification"

    return result


async def _tokens_for_contact(
    session: AsyncSession, contact: EmergencyContact
) -> Sequence[FcmToken]:
    """FCM tokens belonging to the contact, when the contact happens to have
    a SafeHer account of their own.

    Matched on phone first and email second — the phone number is the field
    the app requires, so it is the one that is reliably present.
    """
    clauses = []
    if contact.phone:
        clauses.append(User.phone == contact.phone)
    if contact.email:
        clauses.append(User.email == contact.email)
    if not clauses:
        return []

    matched = (await session.execute(select(User).where(or_(*clauses)))).scalars().first()
    if matched is None:
        return []
    return (
        (await session.execute(select(FcmToken).where(FcmToken.user_id == matched.id)))
        .scalars()
        .all()
    )


async def _with_retries(action) -> Optional[str]:
    """Runs [action] up to [MAX_ATTEMPTS] times.

    Returns None on success, or a human-readable reason for the final
    failure. Never raises: the caller is mid-emergency and needs a report,
    not an exception.
    """
    last_error = "Unknown error"
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            await action()
            return None
        except (SmsNotConfigured, OneSignalNotConfigured, EmailNotConfigured) as exc:
            # Not worth retrying: configuration will not appear mid-alert.
            return str(exc)
        except (SmsDeliveryError, OneSignalDeliveryError, EmailDeliveryError) as exc:
            last_error = str(exc)
        except Exception as exc:  # noqa: BLE001 - dispatch must never crash
            last_error = f"{type(exc).__name__}: {exc}"

        if attempt < MAX_ATTEMPTS:
            await asyncio.sleep(RETRY_DELAY_SECONDS)

    logger.warning("Emergency notification failed after %s attempts: %s", MAX_ATTEMPTS, last_error)
    return last_error


async def _log(
    session: AsyncSession,
    user_id: str,
    channel: str,
    status: str,
    incident_id: str,
    contact_id: str,
    reason: Optional[str] = None,
) -> None:
    """Appends an audit row.

    The payload records ids, and — on a failure — why. It used to record only
    "failed", which is what an alert that reached nobody looked like from the
    database: a row saying something went wrong, with no way to tell a wrong
    password from a blocked port from an unreachable host. Diagnosing one real
    outage meant reproducing it by hand against production.

    Reasons are truncated and come from exception text, never from the message
    body: that body carries the user's live location, and the contact's phone
    number is already on the contact row. Copying either into a log table
    would spread the most sensitive data in the system across another store
    for no operational gain.
    """
    session.add(
        NotificationLog(
            user_id=user_id,
            channel=channel,
            status=status,
            payload=(
                f"incident={incident_id} contact={contact_id}"
                + (f" reason={reason[:160]}" if reason else "")
            ),
        )
    )
    await session.commit()


async def send_evidence_followup(
    *,
    session: AsyncSession,
    settings: Settings,
    user: User,
    incident_id: str,
    share_url: str,
    email_sender=None,
) -> DispatchReport:
    """Tells the contacts already alerted that evidence is now available.

    FR-EMG-05 wants the evidence URL in the alert itself. It cannot be: the
    alert goes out the instant the countdown ends, while the recording is
    still being made. Holding the alert back until the audio existed would
    trade the requirement that matters (speed) for the one that does not.

    So the URL follows in a second message. Only contacts with an email are
    written to -- SMS is a per-message cost and a second text saying
    "there is also a recording" is not worth what the first one is worth.
    """
    contacts = await contacts_repo.list_by_user(session, user_id=user.id)
    report = DispatchReport()
    if not contacts:
        return report

    emailer = email_sender or build_email_sender(
        settings,
        onesignal_sender=OneSignalEmailSender(
            app_id=settings.onesignal_app_id,
            api_key=settings.onesignal_api_key,
        ),
    )

    display_name = (user.full_name or user.email or "A SafeHer user").strip()
    subject = f"Evidence from {display_name}'s SafeHer alert"

    for contact in contacts:
        result = ContactDispatchResult(contact_id=contact.id, contact_name=contact.name)
        if contact.email and emailer is not None and emailer.is_configured:
            body = build_evidence_followup_email(
                user_name=display_name, contact_name=contact.name, share_url=share_url
            )
            error = await _with_retries(
                lambda: emailer.send(to=contact.email, subject=subject, html_body=body)
            )
            if error is None:
                result.delivered_channels.append("email")
                await _log(session, user.id, "email", "evidence_sent", incident_id, contact.id)
            else:
                result.failures["email"] = error
                await _log(session, user.id, "email", "evidence_failed", incident_id, contact.id, reason=error)
        else:
            result.failures["email"] = "No email address for this contact"
        report.results.append(result)

    return report


def build_evidence_followup_email(
    *, user_name: str, contact_name: str, share_url: str
) -> str:
    import html as _html

    safe_user = _html.escape(user_name)
    safe_contact = _html.escape(contact_name)
    safe_url = _html.escape(share_url)
    return f"""<html><body style="font-family:system-ui,-apple-system,sans-serif;
line-height:1.5;color:#18181B">
<p style="margin:0 0 12px">Hi {safe_contact},</p>
<p style="margin:0 0 12px">A recording was captured during {safe_user}'s
SafeHer alert. You can listen to it and see the full report here:</p>
<p style="margin:16px 0"><a href="{safe_url}"
style="background:#7C3AED;color:#fff;padding:12px 20px;border-radius:8px;
text-decoration:none;display:inline-block">Open the report</a></p>
<p style="margin:16px 0;color:#666">This link expires in 7 days and can be
revoked at any time. If {safe_user} has not been in touch, contact your
local emergency services.</p>
</body></html>"""
