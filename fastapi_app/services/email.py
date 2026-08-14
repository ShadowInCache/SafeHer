"""Transactional email delivery over SMTP.

Deliberately has no "pretend to send" mode. If SMTP is unconfigured, callers
are told so and decide what to do; silently dropping a verification code would
leave a user waiting forever for an email that was never sent.
"""

from __future__ import annotations

import asyncio
from email.message import EmailMessage
import logging
import smtplib

from fastapi_app.config import Settings

logger = logging.getLogger(__name__)


class EmailNotConfigured(RuntimeError):
    """Raised when a send is attempted without SMTP settings."""


class EmailDeliveryError(RuntimeError):
    """Raised when the SMTP server refused or dropped the message."""


def _build_message(*, settings: Settings, to: str, subject: str, body: str) -> EmailMessage:
    message = EmailMessage()
    message["From"] = f"{settings.smtp_from_name} <{settings.smtp_from_email}>"
    message["To"] = to
    message["Subject"] = subject
    message.set_content(body)
    return message


def _send_blocking(settings: Settings, message: EmailMessage) -> None:
    if settings.smtp_use_tls:
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=15) as client:
            client.starttls()
            if settings.smtp_username:
                client.login(settings.smtp_username, settings.smtp_password or "")
            client.send_message(message)
    else:
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=15) as client:
            if settings.smtp_username:
                client.login(settings.smtp_username, settings.smtp_password or "")
            client.send_message(message)


async def send_email(*, settings: Settings, to: str, subject: str, body: str) -> None:
    """Send one message, off the event loop.

    `smtplib` is blocking, so it runs in a worker thread; doing it inline would
    stall every other request for the duration of the SMTP handshake.
    """
    if not settings.smtp_configured:
        raise EmailNotConfigured("SMTP_HOST and SMTP_FROM_EMAIL are not set")

    message = _build_message(settings=settings, to=to, subject=subject, body=body)
    try:
        await asyncio.to_thread(_send_blocking, settings, message)
    except (smtplib.SMTPException, OSError) as exc:
        logger.warning("SMTP delivery to %s failed: %s", to, exc)
        raise EmailDeliveryError(str(exc)) from exc


async def send_verification_code(*, settings: Settings, to: str, code: str) -> None:
    minutes = settings.email_otp_ttl_minutes
    await send_email(
        settings=settings,
        to=to,
        subject="Your SafeHer verification code",
        body=(
            f"Your SafeHer verification code is {code}\n\n"
            f"It expires in {minutes} minutes. If you did not create a SafeHer "
            "account, you can ignore this email.\n"
        ),
    )
