"""UTC helpers for anything that leaves the server.

Timestamps are stored naive throughout this system but always *mean* UTC (see
`models._utcnow`). That is fine inside the process, where every comparison has
the same convention on both sides. It stops being fine the moment a timestamp
is written into JSON.

An ISO string with no offset — `2026-10-09T08:44:00` — is read as *local time*
by Dart's `DateTime.parse` and by JavaScript's `Date`. A phone in IST therefore
places a journey that started seconds ago five and a half hours in the past,
and shows it as long overdue. Anything bound for a client goes through here.

Pydantic response models get the same treatment via `schemas.UtcDatetime`;
these helpers cover the payloads that are built by hand, such as WebSocket
broadcasts and push notification bodies.
"""

from datetime import datetime, timezone
from typing import Optional


def as_utc(value: datetime) -> datetime:
    """Return `value` as an aware UTC datetime, assuming naive means UTC."""
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def to_utc_iso(value: Optional[datetime]) -> Optional[str]:
    """ISO-8601 with an explicit offset, or None. Safe for any client."""
    return as_utc(value).isoformat() if value is not None else None


def utc_now_iso() -> str:
    """Now, as an unambiguous ISO-8601 string."""
    return datetime.now(timezone.utc).isoformat()
