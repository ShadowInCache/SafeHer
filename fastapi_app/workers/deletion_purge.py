"""Background maintenance for scheduled account deletions.

SRS FR-AUTH-08 gives a 30-day grace period, after which the account must
actually be erased. Without this worker the grace period would never end and
"deletion" would only ever mean "deactivated", which is not GDPR Art. 17
erasure.
"""

from __future__ import annotations

import asyncio
import logging

from fastapi_app.config import get_settings
from fastapi_app.db import SessionLocal
from fastapi_app.repositories import auth_security
from fastapi_app.repositories import users as user_repo

logger = logging.getLogger(__name__)

# Grace periods are measured in days, so hourly is ample and keeps the load
# negligible.
PURGE_INTERVAL_SECONDS = 3600


async def purge_expired_accounts() -> int:
    """Erase accounts whose grace period has elapsed. Returns the count."""
    settings = get_settings()
    purged = 0
    async with SessionLocal() as session:
        due = await auth_security.get_expired_deletions(
            session, grace_days=settings.account_deletion_grace_days
        )
        for user in due:
            email = user.email
            await user_repo.delete_cascade(session, user=user)
            purged += 1
            logger.info("Purged account %s after grace period", email)
    return purged


async def deletion_purge_worker() -> None:
    """Run the purge on a loop until cancelled."""
    while True:
        try:
            count = await purge_expired_accounts()
            if count:
                logger.info("Deletion purge removed %s account(s)", count)
        except asyncio.CancelledError:
            raise
        except Exception:
            # A failed sweep must not kill the loop; the next tick retries.
            logger.exception("Deletion purge sweep failed")
        await asyncio.sleep(PURGE_INTERVAL_SECONDS)
