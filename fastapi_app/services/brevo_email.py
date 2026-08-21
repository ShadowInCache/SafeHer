"""Email over HTTPS, for a host that will not let us speak SMTP.

**Why this module exists.** SafeHer's emergency email and contact
verification both worked perfectly from a laptop and both failed in
production, with `[Errno 101] Network is unreachable` and client-side
timeouts. The credentials were valid and the code was correct. Render's free
web services block outbound traffic on ports 25, 465 and 587 — every port
SMTP speaks — as a policy change from September 2025. There is no setting to
turn that off, and nothing in the code could have worked around it.

Brevo's transactional endpoint is ordinary HTTPS on 443, which no such policy
blocks. That is the entire reason it is here: not better deliverability, not
a nicer API, just a port that is open.

**Why Brevo rather than the alternatives.** OneSignal (already wired up in
`onesignal.py`) requires a sending *domain* verified by SPF/DKIM/DMARC and
explicitly refuses Gmail addresses as senders, which is exactly the wall this
project hit before. Brevo's free tier verifies an individual sender address —
an ordinary mailbox — and allows 300 messages a day, which is far more than a
safety app's emergency traffic and costs nothing.

**What it does not fix.** Email remains a weaker emergency channel than SMS;
nobody watches an inbox the way they notice a text. This makes the free
channel actually arrive. It does not make it the right primary channel, and
`emergency_dispatch.py` still ranks SMS above it.
"""

from __future__ import annotations

import logging
from typing import Optional

import httpx

logger = logging.getLogger(__name__)

BREVO_API_ROOT = "https://api.brevo.com/v3"


class BrevoNotConfigured(RuntimeError):
    """Raised when the Brevo API key or sender address is absent."""


class BrevoDeliveryError(RuntimeError):
    """Raised when Brevo refuses the message."""


class BrevoEmailSender:
    """Thin wrapper over `POST /smtp/email`.

    Matches the shape of `SmtpEmailSender` and `OneSignalEmailSender` —
    `is_configured` and `send` — so `emergency_dispatch` can hold any of the
    three without knowing which.
    """

    def __init__(
        self,
        *,
        api_key: Optional[str],
        from_email: Optional[str],
        from_name: str = "SafeHer",
        timeout_seconds: float = 10.0,
    ) -> None:
        self._api_key = api_key
        self._from_email = from_email
        self._from_name = from_name
        self._timeout = timeout_seconds

    @property
    def is_configured(self) -> bool:
        return bool(self._api_key and self._from_email)

    async def send(self, *, to: str, subject: str, html_body: str) -> str:
        """Sends one email and returns Brevo's message id."""
        if not self.is_configured:
            raise BrevoNotConfigured(
                "Brevo is not configured. Set BREVO_API_KEY and SMTP_FROM_EMAIL "
                "to send email over HTTPS."
            )

        payload = {
            "sender": {"email": self._from_email, "name": self._from_name},
            "to": [{"email": to}],
            "subject": subject,
            "htmlContent": html_body,
        }
        headers = {
            "api-key": self._api_key,
            "content-type": "application/json",
            "accept": "application/json",
        }

        try:
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                response = await client.post(
                    f"{BREVO_API_ROOT}/smtp/email", json=payload, headers=headers
                )
        except httpx.HTTPError as exc:
            raise BrevoDeliveryError(f"Brevo was unreachable: {exc}") from exc

        if response.status_code >= 400:
            # The body carries Brevo's reason — an unverified sender, a bad
            # key, a daily cap. Surfaced rather than swallowed, because
            # `_log` in emergency_dispatch records it and the whole point of
            # that column is that a failed alert says why it failed.
            raise BrevoDeliveryError(
                f"Brevo refused the message ({response.status_code}): {response.text[:200]}"
            )

        try:
            return str(response.json().get("messageId", ""))
        except ValueError:
            # Accepted, but the body was not JSON. The send succeeded, which
            # is what the caller needs; the id is a convenience.
            return ""
