"""Per-contact confirmation codes — SRS FR-EMG-10.

An emergency contact is only useful if the address actually reaches the
person the user had in mind. The commonest failure is not a hostile one: it
is a typo nobody notices until the day it matters, when an alert goes to a
stranger's inbox and the person who could have helped hears nothing.

The flow is deliberately the low-friction one. SafeHer emails the contact a
six-digit code and asks them to pass it to the person who added them; the
user types it in. The contact needs no account and no app — asking a
sister to install software before she can be an emergency contact is how
contact lists end up empty.

An unverified contact is **still notified** in an emergency. Verification
tells the user which entries to double-check; it is not a gate on getting
help, because a possibly-wrong address still beats no address when someone
is in danger.
"""

from __future__ import annotations

import html
import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.config import Settings
from fastapi_app.models import EmergencyContact
from fastapi_app.repositories.auth_security import generate_code
from fastapi_app.security import get_password_hash, verify_password
from fastapi_app.services.onesignal import OneSignalEmailSender
from fastapi_app.services.smtp_email import build_email_sender

logger = logging.getLogger(__name__)

CODE_TTL_MINUTES = 30

# Generous compared with a login: the code travels via a third person, and
# locking a user out of confirming her sister after three fat-fingered
# attempts helps nobody. Still bounded, so the six-digit space cannot be
# walked.
MAX_ATTEMPTS = 10


class ContactVerificationError(RuntimeError):
    """Raised when a code cannot be issued or checked."""


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def build_verification_email(*, user_name: str, contact_name: str, code: str) -> tuple[str, str]:
    subject = f"{user_name} added you as their SafeHer emergency contact"
    safe_user = html.escape(user_name)
    safe_contact = html.escape(contact_name)
    body = f"""<html><body style="font-family:system-ui,-apple-system,sans-serif;
line-height:1.5;color:#18181B">
<p style="margin:0 0 12px">Hi {safe_contact},</p>
<p style="margin:0 0 12px">{safe_user} has listed you as an emergency contact
in SafeHer, a personal safety app. If they ever trigger an alert, you will
be emailed their location so you can help.</p>
<p style="margin:0 0 8px">To confirm this address works, give them this code:</p>
<p style="margin:0 0 16px;font-size:30px;font-weight:700;letter-spacing:6px;
font-family:ui-monospace,monospace">{html.escape(code)}</p>
<p style="margin:0;color:#666">The code expires in {CODE_TTL_MINUTES} minutes.
If you don't know {safe_user}, you can ignore this email — you will not be
contacted again unless they confirm.</p>
</body></html>"""
    return subject, body


async def send_verification_code(
    session: AsyncSession,
    *,
    settings: Settings,
    contact: EmergencyContact,
    user_name: str,
    email_sender=None,
) -> None:
    """Issues a fresh code and emails it to the contact.

    Raises [ContactVerificationError] when there is no address to send to or
    no configured way to send it — never silently succeeds, because a user
    who thinks a code is on its way will sit waiting for one.
    """
    if not contact.email:
        raise ContactVerificationError(
            "This contact has no email address, so there is nothing to send a code to."
        )

    sender = email_sender or build_email_sender(
        settings,
        onesignal_sender=OneSignalEmailSender(
            app_id=settings.onesignal_app_id,
            api_key=settings.onesignal_api_key,
        ),
    )
    if sender is None or not sender.is_configured:
        raise ContactVerificationError("Email is not configured, so no code can be sent.")

    code = generate_code()
    subject, body = build_verification_email(
        user_name=user_name, contact_name=contact.name, code=code
    )
    await sender.send(to=contact.email, subject=subject, html_body=body)

    # Written only after a successful send. Storing first would leave a
    # live code against a contact who never received one, and the attempt
    # counter would start burning down on a code nobody has.
    contact.verification_code_hash = get_password_hash(code)
    contact.verification_expires_at = _utcnow() + timedelta(minutes=CODE_TTL_MINUTES)
    contact.verification_attempts = 0
    await session.commit()


async def confirm_verification_code(
    session: AsyncSession, *, contact: EmergencyContact, code: str
) -> bool:
    """Checks [code] and marks the contact verified on success."""
    if contact.verification_code_hash is None:
        raise ContactVerificationError("No code has been sent to this contact yet.")

    expires_at: Optional[datetime] = contact.verification_expires_at
    if expires_at is not None and _utcnow() > expires_at:
        raise ContactVerificationError("That code has expired. Send a new one.")

    if contact.verification_attempts >= MAX_ATTEMPTS:
        raise ContactVerificationError("Too many attempts. Send a new code.")

    if not verify_password(code, contact.verification_code_hash):
        contact.verification_attempts += 1
        await session.commit()
        return False

    contact.verified_at = _utcnow()
    # The code is single-use: clearing it means a replay of the same email
    # cannot re-verify a contact whose address was changed afterwards.
    contact.verification_code_hash = None
    contact.verification_expires_at = None
    contact.verification_attempts = 0
    await session.commit()
    return True


def invalidate_verification(contact: EmergencyContact) -> None:
    """Drops verification after the address changes.

    A contact verified at one address tells you nothing about a different
    one, and leaving the tick in place would hide exactly the typo this
    feature exists to catch.
    """
    contact.verified_at = None
    contact.verification_code_hash = None
    contact.verification_expires_at = None
    contact.verification_attempts = 0
