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


def naive_utc_now() -> datetime:
    """Now, as a naive datetime that means UTC — the storage convention.

    Use this for anything written to a `DateTime` column, so that every
    comparison in the process has the same convention on both sides.

    Deliberately not `datetime.utcnow()`, which returns the same value but is
    deprecated and scheduled for removal. Five modules had each defined this
    helper privately and two of them were still built on `utcnow()`; one
    definition is harder to get inconsistently wrong than five.
    """
    return datetime.now(timezone.utc).replace(tzinfo=None)


def utc_epoch_seconds() -> int:
    """Seconds since the Unix epoch, for signing and anything time-boxed.

    Never build this from a naive datetime. `datetime.utcnow().timestamp()`
    looks correct and is not: `.timestamp()` interprets a naive datetime as
    *local* time, so the result is wrong by the host's UTC offset. On an
    IST server it came out 19,800 seconds — five and a half hours — in the
    past.

    That broke Cloudinary's signed direct uploads, which reject a signature
    whose timestamp is more than about an hour from their clock. The practical
    effect was that evidence upload signing failed on any server not running in
    UTC, while working perfectly on one that was.
    """
    return int(datetime.now(timezone.utc).timestamp())


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
