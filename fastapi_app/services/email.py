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


def _build_message(
    *, settings: Settings, to: str, subject: str, body: str, html_body: str | None = None
) -> EmailMessage:
    message = EmailMessage()
    message["From"] = f"{settings.smtp_from_name} <{settings.smtp_from_email}>"
    message["To"] = to
    message["Subject"] = subject
    # Plain text is always set first and stays the fallback part: an
    # emergency alert has to be readable on a client that refuses HTML, and
    # a multipart/alternative with no text part is a common spam signal.
    message.set_content(body)
    if html_body:
        message.add_alternative(html_body, subtype="html")
    return message


def _attach_all(message: EmailMessage, attachments) -> None:
    """Adds each `(filename, content)` as a binary attachment.

    Typed as octet-stream rather than sniffed: the only caller sends a PDF,
    and guessing a type from a filename is how a renamed file ends up
    mislabelled in someone's mail client.
    """
    for name, content in attachments or ():
        subtype = "pdf" if name.lower().endswith(".pdf") else "octet-stream"
        message.add_attachment(
            content, maintype="application", subtype=subtype, filename=name
        )


def _send_blocking(settings: Settings, message: EmailMessage) -> None:
    """Deliver over whichever TLS style the port implies.

    Port 465 speaks TLS from the first byte (SMTPS); 587 and 25 start in the
    clear and upgrade with STARTTLS. The distinction matters more than it
    looks: many consumer ISPs block 25 and 587 outright as an anti-spam
    measure while leaving 465 open, so a deployment that only knows how to
    STARTTLS simply times out with no useful error. That is exactly what
    happened here.
    """
    if settings.smtp_use_ssl:
        with smtplib.SMTP_SSL(settings.smtp_host, settings.smtp_port, timeout=settings.smtp_timeout_seconds) as client:
            if settings.smtp_username:
                client.login(settings.smtp_username, settings.smtp_password or "")
            client.send_message(message)
        return

    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=settings.smtp_timeout_seconds) as client:
        if settings.smtp_use_tls:
            client.starttls()
        if settings.smtp_username:
            client.login(settings.smtp_username, settings.smtp_password or "")
        client.send_message(message)


async def send_email(
    *,
    settings: Settings,
    to: str,
    subject: str,
    body: str,
    html_body: str | None = None,
    attachments=None,
) -> None:
    """Send one message, off the event loop.

    `smtplib` is blocking, so it runs in a worker thread; doing it inline would
    stall every other request for the duration of the SMTP handshake.
    """
    # HTTPS first when it is available. Everything this function sends — the
    # sign-up OTP, the lockout notice, the password reset — died silently in
    # production for the same reason the emergency email did: the host blocks
    # every SMTP port, so a correct implementation with valid credentials
    # simply hung. See `brevo_email.py`.
    if settings.brevo_configured:
        from fastapi_app.services.brevo_email import BrevoDeliveryError, BrevoEmailSender

        sender = BrevoEmailSender(
            api_key=settings.brevo_api_key,
            from_email=settings.smtp_from_email,
            from_name=settings.smtp_from_name,
        )
        try:
            await sender.send(
                to=to,
                subject=subject,
                attachments=attachments,
                # Brevo takes HTML. A plain-text-only caller (the OTP mail)
                # gets its newlines preserved rather than collapsed into one
                # run-on line, which is what an unescaped <pre>-less body does.
                html_body=html_body or _as_html(body),
            )
            return
        except BrevoDeliveryError as exc:
            logger.warning("Brevo delivery to %s failed: %s", to, exc)
            # Fall through to SMTP rather than giving up: on a host where SMTP
            # does work, a Brevo outage should not take email down with it.
            if not settings.smtp_configured:
                raise EmailDeliveryError(str(exc)) from exc

    if not settings.smtp_configured:
        raise EmailNotConfigured(
            "No email channel is configured. Set BREVO_API_KEY (HTTPS) or "
            "SMTP_HOST and SMTP_FROM_EMAIL."
        )

    message = _build_message(
        settings=settings, to=to, subject=subject, body=body, html_body=html_body
    )
    _attach_all(message, attachments)
    try:
        await asyncio.to_thread(_send_blocking, settings, message)
    except (smtplib.SMTPException, OSError) as exc:
        logger.warning("SMTP delivery to %s failed: %s", to, exc)
        raise EmailDeliveryError(str(exc)) from exc


def _as_html(body: str) -> str:
    """Wraps a plain-text body for a channel that only takes HTML.

    Escaped, then line breaks restored. Escaping matters even here: a
    verification mail interpolates nothing user-supplied today, but the next
    caller of `send_email` might, and an unescaped body is how that becomes an
    injection into someone's inbox.
    """
    import html as _html

    return "<p>" + _html.escape(body).replace("\n", "<br />") + "</p>"


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
