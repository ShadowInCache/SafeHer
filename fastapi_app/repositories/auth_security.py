"""Persistence for login lockout, email OTPs, and scheduled account deletion.

Kept out of the router so the policy is testable without HTTP, and out of
`users.py` so profile CRUD does not grow security state handling.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import secrets
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.models import EmailVerificationCode, User
from fastapi_app.security import get_password_hash, verify_password

# Stored datetimes are naive UTC to match the rest of the schema; comparing a
# naive column against an aware `now` raises on Postgres.
def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


# ---------------------------------------------------------------- login lockout


def is_locked(user: User) -> bool:
    return user.locked_until is not None and user.locked_until > _utcnow()


def lock_seconds_remaining(user: User) -> int:
    if not is_locked(user):
        return 0
    return max(0, int((user.locked_until - _utcnow()).total_seconds()))


async def register_failed_login(
    session: AsyncSession, *, user: User, max_attempts: int, lockout_minutes: int
) -> bool:
    """Count a failed attempt; lock the account once the threshold is hit.

    Returns True if this attempt caused a lockout, so the caller can send the
    notification required by FR-AUTH-07 exactly once per lockout.
    """
    user.failed_login_attempts = (user.failed_login_attempts or 0) + 1
    just_locked = False
    if user.failed_login_attempts >= max_attempts:
        user.locked_until = _utcnow() + timedelta(minutes=lockout_minutes)
        user.failed_login_attempts = 0
        just_locked = True
    await session.commit()
    await session.refresh(user)
    return just_locked


async def clear_failed_logins(session: AsyncSession, *, user: User) -> None:
    if user.failed_login_attempts or user.locked_until:
        user.failed_login_attempts = 0
        user.locked_until = None
        await session.commit()
        await session.refresh(user)


# ------------------------------------------------------------- email OTP codes

PURPOSE_VERIFY_EMAIL = "email_verification"
PURPOSE_RESET_PASSWORD = "password_reset"


def generate_code() -> str:
    """A 6-digit code from a CSPRNG.

    `secrets` rather than `random`: the module-level Mersenne Twister is
    predictable from prior outputs, which would make codes guessable.
    """
    return f"{secrets.randbelow(1_000_000):06d}"


async def issue_verification_code(
    session: AsyncSession,
    *,
    user: User,
    ttl_minutes: int,
    purpose: str = PURPOSE_VERIFY_EMAIL,
) -> str:
    """Invalidate outstanding codes for this purpose and issue a fresh one.

    Scoped by purpose so requesting a password reset does not silently cancel a
    pending email verification, or vice versa.
    """
    outstanding = await session.execute(
        select(EmailVerificationCode).where(
            EmailVerificationCode.user_id == user.id,
            EmailVerificationCode.purpose == purpose,
            EmailVerificationCode.consumed_at.is_(None),
        )
    )
    now = _utcnow()
    for record in outstanding.scalars():
        record.consumed_at = now

    code = generate_code()
    session.add(
        EmailVerificationCode(
            user_id=user.id,
            code_hash=get_password_hash(code),
            purpose=purpose,
            expires_at=now + timedelta(minutes=ttl_minutes),
        )
    )
    await session.commit()
    return code


async def verify_code(
    session: AsyncSession,
    *,
    user: User,
    code: str,
    max_attempts: int,
    purpose: str = PURPOSE_VERIFY_EMAIL,
) -> tuple[bool, str]:
    """Check `code` against the outstanding OTP for `purpose`.

    Returns (ok, reason). The code is consumed on success, and also once the
    attempt budget is spent, so a burnt code cannot be brute-forced further.
    """
    result = await session.execute(
        select(EmailVerificationCode)
        .where(
            EmailVerificationCode.user_id == user.id,
            EmailVerificationCode.purpose == purpose,
            EmailVerificationCode.consumed_at.is_(None),
        )
        .order_by(EmailVerificationCode.created_at.desc())
    )
    record = result.scalars().first()
    if record is None:
        return False, "no_code"

    now = _utcnow()
    if record.expires_at <= now:
        record.consumed_at = now
        await session.commit()
        return False, "expired"

    if record.attempts >= max_attempts:
        record.consumed_at = now
        await session.commit()
        return False, "too_many_attempts"

    if not verify_password(code, record.code_hash):
        record.attempts += 1
        if record.attempts >= max_attempts:
            record.consumed_at = now
        await session.commit()
        return False, "invalid"

    record.consumed_at = now
    if purpose == PURPOSE_VERIFY_EMAIL:
        user.is_verified = True
    await session.commit()
    await session.refresh(user)
    return True, "ok"


# ------------------------------------------------- password change / revocation


async def set_password(session: AsyncSession, *, user: User, new_password: str) -> None:
    """Change the password and revoke every existing session (FR-AUTH-06).

    `tokens_valid_from` moves forward, which invalidates tokens already issued
    to other devices without maintaining a JWT blacklist.
    """
    user.password_hash = get_password_hash(new_password)
    user.tokens_valid_from = _utcnow()
    user.failed_login_attempts = 0
    user.locked_until = None
    await session.commit()
    await session.refresh(user)


# ------------------------------------------------------- deletion grace period


async def request_deletion(session: AsyncSession, *, user: User) -> datetime:
    """Schedule deletion and revoke sessions. Returns the purge date."""
    now = _utcnow()
    user.deletion_requested_at = now
    user.is_active = False
    user.tokens_valid_from = now
    await session.commit()
    await session.refresh(user)
    return now


async def cancel_deletion(session: AsyncSession, *, user: User) -> None:
    user.deletion_requested_at = None
    user.is_active = True
    await session.commit()
    await session.refresh(user)


async def get_expired_deletions(
    session: AsyncSession, *, grace_days: int
) -> list[User]:
    """Accounts whose grace period has fully elapsed and are due for purge."""
    cutoff = _utcnow() - timedelta(days=grace_days)
    result = await session.execute(
        select(User).where(
            User.deletion_requested_at.is_not(None),
            User.deletion_requested_at <= cutoff,
        )
    )
    return list(result.scalars())


async def get_by_email_for_update(session: AsyncSession, email: str) -> Optional[User]:
    result = await session.execute(select(User).where(User.email == email))
    return result.scalars().first()
