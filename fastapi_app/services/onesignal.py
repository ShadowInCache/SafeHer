"""OneSignal-backed email delivery.

Chosen for one reason that matters to this project: OneSignal's free tier
includes 10,000 emails a month, so an emergency can reach a contact who has
an email address without anyone paying a bill.

**Two things OneSignal does not solve.**

*SMS:* its pricing puts SMS at $3 per 1,000 messages, and its free-tier SMS
trial works by connecting *your own Twilio account* — it wraps Twilio rather
than replacing it.

*A domain:* OneSignal email requires a sending domain you own, verified by
SPF/DKIM/DMARC records, and explicitly refuses Gmail and Outlook addresses
as senders. A project with no domain cannot use this path at all, which is
why `smtp_email.py` exists and is tried first — plain SMTP through an
ordinary mailbox needs no domain and no DNS. This module is the better
option once a domain exists, because deliverability from a verified sending
domain beats a personal mailbox.

Email is a weaker emergency channel than SMS and is treated as one: people
do not watch an inbox the way they notice a text. It is a real additional
channel, not a substitute, and the dispatch report never counts an email as
equivalent to reaching someone's phone.
"""

from __future__ import annotations

import html
import logging
from typing import Optional

import httpx

logger = logging.getLogger(__name__)

ONESIGNAL_API_ROOT = "https://api.onesignal.com"


class OneSignalNotConfigured(RuntimeError):
    """Raised when the OneSignal app id or API key is absent."""


class OneSignalDeliveryError(RuntimeError):
    """Raised when OneSignal refuses the message."""


class OneSignalEmailSender:
    """Thin wrapper over `POST /notifications` in email mode."""

    def __init__(
        self,
        *,
        app_id: Optional[str],
        api_key: Optional[str],
        from_name: str = "SafeHer",
        timeout_seconds: float = 10.0,
    ) -> None:
        self._app_id = app_id
        self._api_key = api_key
        self._from_name = from_name
        self._timeout = timeout_seconds

    @property
    def is_configured(self) -> bool:
        return bool(self._app_id and self._api_key)

    async def send(self, *, to: str, subject: str, html_body: str) -> str:
        """Sends one email and returns OneSignal's notification id."""
        if not self.is_configured:
            raise OneSignalNotConfigured(
                "OneSignal is not configured. Set ONESIGNAL_APP_ID and "
                "ONESIGNAL_API_KEY to send emergency email."
            )

        payload = {
            "app_id": self._app_id,
            "email_to": [to],
            "email_subject": subject,
            "email_body": html_body,
        }
        headers = {
            # OneSignal's current scheme is `Key <token>`, not the older
            # `Basic <token>`. Getting this wrong returns a 401 that reads
            # like a bad key rather than a bad header.
            "Authorization": f"Key {self._api_key}",
            "Content-Type": "application/json",
        }

        try:
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                response = await client.post(
                    f"{ONESIGNAL_API_ROOT}/notifications", json=payload, headers=headers
                )
        except httpx.HTTPError as exc:
            raise OneSignalDeliveryError(f"Could not reach OneSignal: {exc}") from exc

        if response.status_code >= 300:
            # The error body echoes the recipient address, so only the
            # status is logged — an emergency contact's email is no less
            # sensitive than their phone number.
            logger.warning("OneSignal rejected an emergency email: status=%s", response.status_code)
            raise OneSignalDeliveryError(
                f"OneSignal rejected the message (HTTP {response.status_code})."
            )

        body = response.json()
        # A 200 with an `errors` array is still a failure — OneSignal
        # reports "no recipients" and invalid-address cases this way, and
        # treating it as success would put a phantom delivery in the report.
        if body.get("errors"):
            raise OneSignalDeliveryError("OneSignal accepted the request but delivered to nobody.")
        return body.get("id", "")


def build_emergency_email(
    *,
    user_name: str,
    contact_name: str,
    maps_url: Optional[str],
    local_time: str,
    evidence_url: Optional[str] = None,
) -> tuple[str, str]:
    """Returns `(subject, html_body)` for an emergency email.

    Everything a reader needs is in the subject line, because that is all
    that shows on a locked phone: who, and that it is an emergency. The body
    exists for the location link.
    """
    safe_user = html.escape(user_name)
    safe_contact = html.escape(contact_name)
    subject = f"EMERGENCY: {user_name} needs help now"

    location_block = (
        f'<p style="margin:16px 0"><a href="{html.escape(maps_url)}" '
        f'style="background:#7C3AED;color:#fff;padding:12px 20px;'
        f'border-radius:8px;text-decoration:none;display:inline-block">'
        f"See their location</a></p>"
        if maps_url
        else '<p style="margin:16px 0;color:#666">No location was available '
        "when the alert was sent.</p>"
    )
    evidence_block = (
        f'<p style="margin:8px 0"><a href="{html.escape(evidence_url)}">'
        f"View recorded evidence</a></p>"
        if evidence_url
        else ""
    )

    body = f"""<html><body style="font-family:system-ui,-apple-system,sans-serif;
line-height:1.5;color:#18181B">
<p style="margin:0 0 8px">Hi {safe_contact},</p>
<h2 style="margin:0 0 8px;color:#E53935">{safe_user} has triggered a SafeHer emergency alert.</h2>
<p style="margin:0;color:#666">Sent at {html.escape(local_time)}.</p>
{location_block}
{evidence_block}
<p style="margin:16px 0;color:#666">You are receiving this because
{safe_user} listed you as an emergency contact. If you cannot reach them,
contact your local emergency services.</p>
</body></html>"""
    return subject, body
