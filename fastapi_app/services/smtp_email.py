"""Emergency email over plain SMTP.

The channel that works when nothing else is affordable.

OneSignal's free tier is generous but needs a sending domain you own with
SPF/DKIM/DMARC records, and it refuses Gmail and Outlook as senders. SMS
costs money with every provider. An ordinary mailbox and an app password
need neither a domain nor a budget, which makes this the only emergency
channel a project can stand up on day one.

Deliverability is worse than a verified sending domain — a personal mailbox
sending alert-shaped mail is more likely to be filtered — so
`emergency_dispatch.py` prefers this only because it is the one that can
actually be configured. Move to `onesignal.py` once a domain exists.
"""

from __future__ import annotations

from typing import Optional

from fastapi_app.config import Settings
from fastapi_app.services.email import EmailDeliveryError, EmailNotConfigured, send_email


class SmtpEmailSender:
    """Adapter matching `OneSignalEmailSender`'s shape, so the dispatcher can
    hold either without knowing which.
    """

    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    @property
    def is_configured(self) -> bool:
        return self._settings.smtp_configured

    async def send(self, *, to: str, subject: str, html_body: str) -> str:
        if not self.is_configured:
            raise EmailNotConfigured("SMTP_HOST and SMTP_FROM_EMAIL are not set")
        await send_email(
            settings=self._settings,
            to=to,
            subject=subject,
            body=plain_text_fallback(subject=subject, html_body=html_body),
            html_body=html_body,
        )
        # SMTP has no message id to hand back the way a REST API does; the
        # absence of an exception is the receipt.
        return ""


def plain_text_fallback(*, subject: str, html_body: str) -> str:
    """A readable text part for clients that will not render HTML.

    Built from the subject plus any links in the body rather than by
    stripping tags: the one thing a reader must be able to act on is the
    location URL, and a naive tag strip tends to lose exactly that.
    """
    import re

    links = re.findall(r'href="([^"]+)"', html_body)
    lines = [subject, ""]
    for link in links:
        lines.append(link)
    lines.append("")
    lines.append("Sent by SafeHer because you are listed as an emergency contact.")
    return "\n".join(lines)


def build_email_sender(settings: Settings, *, onesignal_sender=None):
    """Picks the email channel to use.

    SMTP first, not because it is better but because it is the one that can
    be configured without a domain. Falls back to OneSignal, which has the
    better deliverability once a sending domain is verified.
    """
    smtp = SmtpEmailSender(settings)
    if smtp.is_configured:
        return smtp
    return onesignal_sender


__all__ = [
    "EmailDeliveryError",
    "EmailNotConfigured",
    "SmtpEmailSender",
    "build_email_sender",
    "plain_text_fallback",
]
