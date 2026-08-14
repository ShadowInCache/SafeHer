"""Emergency cancel PIN, phone-side trigger preferences, and nearby safety
locations.

The PIN endpoints deliberately live server-side: a cancel code that only ever
existed in device preferences could be read or cleared by anyone holding the
unlocked phone, which is exactly the situation it is meant to protect against.
"""

import logging

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.db import get_session
from fastapi_app.repositories import safety as safety_repo
from fastapi_app.schemas import (
    NearbyPlace,
    SafetyPinSetRequest,
    SafetyPinStatus,
    SafetyPinVerifyRequest,
    SafetyPinVerifyResponse,
    SafetyPreferences,
    SafetyPreferencesUpdate,
    UserPublic,
)
from fastapi_app.security import get_current_user, get_password_hash, verify_password
from fastapi_app.services import places as places_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/safety", tags=["safety"])


# ---------------------------------------------------------------------- the PIN


@router.get("/pin", response_model=SafetyPinStatus)
async def get_pin_status(
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    pin = await safety_repo.get_pin(session, user_id=current_user.id)
    if pin is None:
        return SafetyPinStatus(is_set=False)

    locked = safety_repo.pin_is_locked(pin)
    return SafetyPinStatus(
        is_set=True,
        is_locked=locked,
        locked_until=pin.locked_until if locked else None,
    )


@router.put("/pin", response_model=SafetyPinStatus)
async def set_pin(
    payload: SafetyPinSetRequest,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    """Create or change the cancel PIN. Changing an existing PIN requires the
    current one — otherwise anyone with the unlocked phone could silently
    replace it."""
    existing = await safety_repo.get_pin(session, user_id=current_user.id)

    if existing is not None:
        if not payload.current_pin:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Current PIN is required to change it",
            )
        if not verify_password(payload.current_pin, existing.pin_hash):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED, detail="Current PIN is incorrect"
            )

    await safety_repo.upsert_pin(
        session, user_id=current_user.id, pin_hash=get_password_hash(payload.pin)
    )
    return SafetyPinStatus(is_set=True)


@router.delete("/pin", status_code=status.HTTP_204_NO_CONTENT)
async def remove_pin(
    payload: SafetyPinVerifyRequest,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    existing = await safety_repo.get_pin(session, user_id=current_user.id)
    if existing is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No PIN is set")
    if not verify_password(payload.pin, existing.pin_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="PIN is incorrect")

    await safety_repo.delete_pin(session, user_id=current_user.id)
    # Removing the PIN must also clear the setting that depends on it, or the
    # SOS flow would demand a PIN that no longer exists.
    preferences = await safety_repo.get_preferences(session, user_id=current_user.id)
    if preferences is not None and preferences.require_pin_to_cancel:
        await safety_repo.update_preferences(
            session, preferences=preferences, require_pin_to_cancel=False
        )
    return None


@router.post("/pin/verify", response_model=SafetyPinVerifyResponse)
async def verify_pin(
    payload: SafetyPinVerifyRequest,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    pin = await safety_repo.get_pin(session, user_id=current_user.id)
    if pin is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No PIN is set")

    if safety_repo.pin_is_locked(pin):
        return SafetyPinVerifyResponse(valid=False, attempts_remaining=0, locked_until=pin.locked_until)

    if verify_password(payload.pin, pin.pin_hash):
        await safety_repo.reset_pin_failures(session, pin=pin)
        return SafetyPinVerifyResponse(valid=True)

    updated = await safety_repo.register_pin_failure(session, pin=pin)
    remaining = max(0, safety_repo.MAX_PIN_ATTEMPTS - updated.failed_attempts)
    return SafetyPinVerifyResponse(
        valid=False,
        attempts_remaining=remaining,
        locked_until=updated.locked_until if safety_repo.pin_is_locked(updated) else None,
    )


# --------------------------------------------------------------- trigger prefs


@router.get("/preferences", response_model=SafetyPreferences)
async def get_safety_preferences(
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    preferences = await safety_repo.get_or_create_preferences(session, user_id=current_user.id)
    return SafetyPreferences.model_validate(preferences)


@router.patch("/preferences", response_model=SafetyPreferences)
async def update_safety_preferences(
    payload: SafetyPreferencesUpdate,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    preferences = await safety_repo.get_or_create_preferences(session, user_id=current_user.id)

    if payload.require_pin_to_cancel:
        pin = await safety_repo.get_pin(session, user_id=current_user.id)
        if pin is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Set a Safety PIN before requiring it to cancel an alert",
            )

    updated = await safety_repo.update_preferences(
        session,
        preferences=preferences,
        shake_trigger_enabled=payload.shake_trigger_enabled,
        shake_sensitivity=payload.shake_sensitivity,
        voice_commands_enabled=payload.voice_commands_enabled,
        require_pin_to_cancel=payload.require_pin_to_cancel,
        journey_auto_share_location=payload.journey_auto_share_location,
    )
    return SafetyPreferences.model_validate(updated)


# ------------------------------------------------------------- nearby locations


@router.get("/nearby", response_model=list[NearbyPlace])
async def nearby_safety_locations(
    latitude: float = Query(ge=-90, le=90),
    longitude: float = Query(ge=-180, le=180),
    radius_metres: int = Query(default=3000, ge=100, le=20000),
    categories: list[str] | None = Query(default=None),
    _: UserPublic = Depends(get_current_user),
):
    """Real nearby police stations, hospitals, pharmacies, transit stops and
    shelters from OpenStreetMap, sorted by true distance from the caller's
    supplied position.

    An empty list means genuinely nothing matched in range. A data-source
    outage is a 503 so the app can say "couldn't load" instead of showing an
    empty map as if the area had no police station.
    """
    if categories:
        unsupported = set(categories) - set(places_service.SUPPORTED_CATEGORIES)
        if unsupported:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Unsupported categories: {', '.join(sorted(unsupported))}",
            )

    try:
        results = await places_service.find_nearby(
            latitude=latitude,
            longitude=longitude,
            radius_metres=radius_metres,
            categories=categories,
        )
    except places_service.PlacesRateLimited as exc:
        logger.info("Nearby lookup rate-limited: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many nearby lookups right now — try again in a moment",
        ) from exc
    except (httpx.HTTPError, ValueError) as exc:
        logger.warning("Nearby lookup failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Nearby safety data is temporarily unavailable",
        ) from exc

    return [NearbyPlace(**place) for place in results]
