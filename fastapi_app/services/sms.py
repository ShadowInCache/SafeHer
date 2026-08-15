"""Twilio-backed SMS delivery.

SMS is the only emergency channel that reaches a contact who has never heard
of SafeHer, which makes it the backbone of FR-EMG-04 rather than a nicety:
push notifications only land on a phone that has already installed the app
and registered a token.

The module never pretends. With no Twilio credentials configured it raises
[SmsNotConfigured] rather than logging a fake success, so a dispatch report
that says "notified" always means a message actually left the building.
"""

from __future__ import annotations

import logging
from typing import Optional

import httpx

logger = logging.getLogger(__name__)

TWILIO_API_ROOT = "https://api.twilio.com/2010-04-01"

# Twilio charges per segment, and a GSM-7 message splits at 160 characters.
# FR-EMG-05 fixes the budget: "SMS < 160 chars with link".
SMS_SEGMENT_LIMIT = 160


class SmsNotConfigured(RuntimeError):
    """Raised when Twilio credentials are absent."""


class SmsDeliveryError(RuntimeError):
    """Raised when Twilio accepted the request but rejected the message."""


class SmsSender:
    """Thin wrapper over Twilio's Messages resource.

    A class rather than a function so the dispatcher can hold one instance
    across a fan-out to several contacts, and so tests can substitute a fake
    without patching module globals.
    """

    def __init__(
        self,
        *,
        account_sid: Optional[str],
        auth_token: Optional[str],
        from_number: Optional[str],
        timeout_seconds: float = 10.0,
    ) -> None:
        self._account_sid = account_sid
        self._auth_token = auth_token
        self._from_number = from_number
        self._timeout = timeout_seconds

    @property
    def is_configured(self) -> bool:
        return bool(self._account_sid and self._auth_token and self._from_number)

    async def send(self, *, to: str, body: str) -> str:
        """Sends one message and returns Twilio's message SID.

        Raises [SmsNotConfigured] when credentials are missing and
        [SmsDeliveryError] when Twilio refuses the message.
        """
        if not self.is_configured:
            raise SmsNotConfigured(
                "Twilio is not configured. Set TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN "
                "and TWILIO_FROM_NUMBER to send emergency SMS."
            )

        url = f"{TWILIO_API_ROOT}/Accounts/{self._account_sid}/Messages.json"
        try:
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                response = await client.post(
                    url,
                    data={"To": to, "From": self._from_number, "Body": body},
                    auth=(self._account_sid or "", self._auth_token or ""),
                )
        except httpx.HTTPError as exc:
            raise SmsDeliveryError(f"Could not reach Twilio: {exc}") from exc

        if response.status_code >= 300:
            # Twilio's error body echoes the destination number. Log the
            # status and its own error code, never the payload, so an
            # emergency contact's phone number stays out of the log file.
            logger.warning(
                "Twilio rejected an emergency SMS: status=%s code=%s",
                response.status_code,
                _twilio_error_code(response),
            )
            raise SmsDeliveryError(f"Twilio rejected the message (HTTP {response.status_code}).")

        return response.json().get("sid", "")


def _twilio_error_code(response: httpx.Response) -> object:
    try:
        return response.json().get("code")
    except ValueError:
        return None


def build_emergency_sms(
    *,
    user_name: str,
    maps_url: Optional[str],
    local_time: str,
    evidence_url: Optional[str] = None,
) -> str:
    """Composes the alert body for FR-EMG-05.

    The parts are appended in order of how much they help someone reading
    this on a lock screen — who, when, where, then evidence — and the whole
    thing is truncated to one segment. A location link that arrives is worth
    more than an evidence link that pushes the message into a second segment
    it may not survive.
    """
    head = f"SafeHer SOS: {user_name} needs help ({local_time})."
    parts = [head]
    if maps_url:
        parts.append(maps_url)
    if evidence_url:
        parts.append(evidence_url)

    body = " ".join(parts)
    if len(body) <= SMS_SEGMENT_LIMIT:
        return body

    # Drop the evidence link first, then trim the name — never the location.
    body = " ".join([head, maps_url] if maps_url else [head])
    if len(body) <= SMS_SEGMENT_LIMIT:
        return body

    overflow = len(body) - SMS_SEGMENT_LIMIT
    trimmed_name = user_name[: max(1, len(user_name) - overflow - 1)].rstrip()
    head = f"SafeHer SOS: {trimmed_name} needs help ({local_time})."
    return " ".join([head, maps_url] if maps_url else [head])[:SMS_SEGMENT_LIMIT]


def maps_link(latitude: Optional[float], longitude: Optional[float]) -> Optional[str]:
    """Google Maps link for the alert body, or None when there is no fix.

    Six decimal places is roughly 0.1 m — more than enough, and it keeps the
    link short enough to leave room for the rest of the segment.
    """
    if latitude is None or longitude is None:
        return None
    return f"https://maps.google.com/?q={latitude:.6f},{longitude:.6f}"
