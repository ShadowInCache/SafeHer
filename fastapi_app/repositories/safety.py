"""Persistence for the phone-side safety features: cancel PIN, trigger
preferences, and Safe Journeys."""

from datetime import datetime, timedelta, timezone
from typing import Optional, Sequence

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.models import (
    JourneyParticipant,
    Location,
    SafeJourney,
    SafetyPin,
    UserSafetyPreferences,
)

# A wrong PIN during an active SOS must not be a free retry loop, but it also
# must never lock a real user out of cancelling for long — 5 tries, 5 minutes.
MAX_PIN_ATTEMPTS = 5
PIN_LOCKOUT = timedelta(minutes=5)


def _naive_utcnow() -> datetime:
    """Model columns are naive UTC (`datetime.utcnow`); keep comparisons consistent."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


# --------------------------------------------------------------------------- PIN


async def get_pin(session: AsyncSession, *, user_id: str) -> Optional[SafetyPin]:
    result = await session.execute(select(SafetyPin).where(SafetyPin.user_id == user_id))
    return result.scalar_one_or_none()


async def upsert_pin(session: AsyncSession, *, user_id: str, pin_hash: str) -> SafetyPin:
    existing = await get_pin(session, user_id=user_id)
    if existing is None:
        existing = SafetyPin(user_id=user_id, pin_hash=pin_hash)
        session.add(existing)
    else:
        existing.pin_hash = pin_hash
        existing.failed_attempts = 0
        existing.locked_until = None

    await session.commit()
    await session.refresh(existing)
    return existing


async def delete_pin(session: AsyncSession, *, user_id: str) -> bool:
    existing = await get_pin(session, user_id=user_id)
    if existing is None:
        return False
    await session.delete(existing)
    await session.commit()
    return True


async def register_pin_failure(session: AsyncSession, *, pin: SafetyPin) -> SafetyPin:
    pin.failed_attempts += 1
    if pin.failed_attempts >= MAX_PIN_ATTEMPTS:
        pin.locked_until = _naive_utcnow() + PIN_LOCKOUT
    await session.commit()
    await session.refresh(pin)
    return pin


async def reset_pin_failures(session: AsyncSession, *, pin: SafetyPin) -> SafetyPin:
    pin.failed_attempts = 0
    pin.locked_until = None
    await session.commit()
    await session.refresh(pin)
    return pin


def pin_is_locked(pin: SafetyPin) -> bool:
    return pin.locked_until is not None and pin.locked_until > _naive_utcnow()


# ------------------------------------------------------------------- preferences


async def get_preferences(session: AsyncSession, *, user_id: str) -> Optional[UserSafetyPreferences]:
    result = await session.execute(
        select(UserSafetyPreferences).where(UserSafetyPreferences.user_id == user_id)
    )
    return result.scalar_one_or_none()


async def get_or_create_preferences(session: AsyncSession, *, user_id: str) -> UserSafetyPreferences:
    existing = await get_preferences(session, user_id=user_id)
    if existing is not None:
        return existing

    created = UserSafetyPreferences(user_id=user_id)
    session.add(created)
    await session.commit()
    await session.refresh(created)
    return created


async def update_preferences(
    session: AsyncSession,
    *,
    preferences: UserSafetyPreferences,
    shake_trigger_enabled: Optional[bool] = None,
    shake_sensitivity: Optional[int] = None,
    voice_commands_enabled: Optional[bool] = None,
    require_pin_to_cancel: Optional[bool] = None,
    journey_auto_share_location: Optional[bool] = None,
) -> UserSafetyPreferences:
    if shake_trigger_enabled is not None:
        preferences.shake_trigger_enabled = shake_trigger_enabled
    if shake_sensitivity is not None:
        preferences.shake_sensitivity = shake_sensitivity
    if voice_commands_enabled is not None:
        preferences.voice_commands_enabled = voice_commands_enabled
    if require_pin_to_cancel is not None:
        preferences.require_pin_to_cancel = require_pin_to_cancel
    if journey_auto_share_location is not None:
        preferences.journey_auto_share_location = journey_auto_share_location

    await session.commit()
    await session.refresh(preferences)
    return preferences


# ---------------------------------------------------------------------- journeys


async def create_journey(
    session: AsyncSession,
    *,
    user_id: str,
    destination_label: str,
    destination_lat: Optional[float],
    destination_lng: Optional[float],
    expected_duration_minutes: int,
    check_in_interval_minutes: Optional[int],
    contact_ids: Sequence[str],
) -> SafeJourney:
    started = _naive_utcnow()
    journey = SafeJourney(
        user_id=user_id,
        destination_label=destination_label,
        destination_lat=destination_lat,
        destination_lng=destination_lng,
        expected_duration_minutes=expected_duration_minutes,
        check_in_interval_minutes=check_in_interval_minutes,
        status="active",
        started_at=started,
        expected_arrival_at=started + timedelta(minutes=expected_duration_minutes),
    )
    session.add(journey)
    await session.flush()

    for contact_id in contact_ids:
        session.add(JourneyParticipant(journey_id=journey.id, contact_id=contact_id))

    await session.commit()
    await session.refresh(journey)
    return journey


async def get_journey(session: AsyncSession, *, journey_id: str) -> Optional[SafeJourney]:
    return await session.get(SafeJourney, journey_id)


async def get_active_journey(session: AsyncSession, *, user_id: str) -> Optional[SafeJourney]:
    result = await session.execute(
        select(SafeJourney)
        .where(SafeJourney.user_id == user_id, SafeJourney.status.in_(("active", "overdue")))
        .order_by(SafeJourney.started_at.desc())
    )
    return result.scalars().first()


async def list_journeys(session: AsyncSession, *, user_id: str, limit: int = 50) -> list[SafeJourney]:
    result = await session.execute(
        select(SafeJourney)
        .where(SafeJourney.user_id == user_id)
        .order_by(SafeJourney.started_at.desc())
        .limit(limit)
    )
    return list(result.scalars().all())


async def list_participant_ids(session: AsyncSession, *, journey_id: str) -> list[str]:
    result = await session.execute(
        select(JourneyParticipant.contact_id).where(JourneyParticipant.journey_id == journey_id)
    )
    return list(result.scalars().all())


async def set_journey_status(
    session: AsyncSession,
    *,
    journey: SafeJourney,
    status: str,
    ended: bool = False,
) -> SafeJourney:
    journey.status = status
    if ended:
        journey.ended_at = _naive_utcnow()
    if status == "overdue" and journey.escalated_at is None:
        journey.escalated_at = _naive_utcnow()

    await session.commit()
    await session.refresh(journey)
    return journey


async def record_check_in(session: AsyncSession, *, journey: SafeJourney) -> SafeJourney:
    journey.last_check_in_at = _naive_utcnow()
    await session.commit()
    await session.refresh(journey)
    return journey


async def add_journey_location(
    session: AsyncSession,
    *,
    journey: SafeJourney,
    lat: float,
    lng: float,
    accuracy: Optional[float],
) -> Location:
    location = Location(
        user_id=journey.user_id,
        journey_id=journey.id,
        lat=lat,
        lng=lng,
        accuracy=accuracy,
    )
    session.add(location)
    await session.commit()
    await session.refresh(location)
    return location


async def list_journey_locations(
    session: AsyncSession, *, journey_id: str, limit: int = 200
) -> list[Location]:
    result = await session.execute(
        select(Location)
        .where(Location.journey_id == journey_id)
        .order_by(Location.captured_at.asc())
        .limit(limit)
    )
    return list(result.scalars().all())


async def find_overdue_journeys(session: AsyncSession) -> list[SafeJourney]:
    """Active journeys whose deadline has passed and that have not yet been
    escalated. Used by the escalation sweep."""
    now = _naive_utcnow()
    result = await session.execute(
        select(SafeJourney).where(
            SafeJourney.status == "active",
            SafeJourney.expected_arrival_at < now,
        )
    )
    return list(result.scalars().all())
