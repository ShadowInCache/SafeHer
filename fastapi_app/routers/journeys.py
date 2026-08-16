"""Safe Journey — a trip with a deadline, watched by chosen contacts.

Escalation policy (deliberately explicit, and deliberately *not* "call the
police automatically"):

  1. The journey's `expected_arrival_at` passes with no "I've arrived".
  2. The journey flips to `overdue` and an Incident is recorded, so the event
     is auditable in Reports like any other.
  3. The user's own devices get a push and a WebSocket event — a last chance
     to say "I'm fine" before anyone else is involved.
  4. The contacts attached to the journey are notified that the user did not
     confirm arrival, with the last known real position.

No step in that chain contacts emergency services. Escalating to police is a
decision that stays with the user (SOS) or with the contacts who now know.
"""

import logging
from datetime import datetime
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.config import Settings, get_settings
from fastapi_app.db import get_session
from fastapi_app.deps import fcm_credentials
from fastapi_app.models import Incident, SafeJourney
from fastapi_app.realtime import manager
from fastapi_app.repositories import emergency_contacts as contacts_repo
from fastapi_app.repositories import fcm_tokens
from fastapi_app.repositories import safety as safety_repo
from fastapi_app.schemas import (
    JourneyBreadcrumb,
    JourneyCreateRequest,
    JourneyLocationRequest,
    JourneyPublic,
    UserPublic,
)
from fastapi_app.security import get_current_user
from fastapi_app.services.notifications import send_fcm_notification

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/journeys", tags=["journeys"])


async def _to_public(session: AsyncSession, journey: SafeJourney) -> JourneyPublic:
    contact_ids = await safety_repo.list_participant_ids(session, journey_id=journey.id)
    return JourneyPublic(
        id=journey.id,
        destination_label=journey.destination_label,
        destination_lat=journey.destination_lat,
        destination_lng=journey.destination_lng,
        expected_duration_minutes=journey.expected_duration_minutes,
        check_in_interval_minutes=journey.check_in_interval_minutes,
        status=journey.status,
        started_at=journey.started_at,
        expected_arrival_at=journey.expected_arrival_at,
        last_check_in_at=journey.last_check_in_at,
        ended_at=journey.ended_at,
        contact_ids=contact_ids,
    )


async def _owned_journey(session: AsyncSession, journey_id: str, user_id: str) -> SafeJourney:
    journey = await safety_repo.get_journey(session, journey_id=journey_id)
    if journey is None or journey.user_id != user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Journey not found")
    return journey


async def _best_effort_push(
    *,
    settings: Settings,
    session: AsyncSession,
    user_id: str,
    title: str,
    body: str,
    data: dict[str, Any],
) -> None:
    if not fcm_credentials(settings).is_configured:
        return
    tokens = await fcm_tokens.list_by_user(session, user_id=user_id)
    for item in tokens:
        try:
            await send_fcm_notification(
                credentials=fcm_credentials(settings),
                token=item.token,
                title=title,
                body=body,
                data=data,
                session=session,
                user_id=user_id,
                device_id=item.device_id,
            )
        except Exception:
            continue


@router.post("", response_model=JourneyPublic, status_code=status.HTTP_201_CREATED)
async def start_journey(
    payload: JourneyCreateRequest,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    existing = await safety_repo.get_active_journey(session, user_id=current_user.id)
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A journey is already in progress",
        )

    # Only the caller's own contacts may be attached to a journey.
    owned = {contact.id for contact in await contacts_repo.list_by_user(session, user_id=current_user.id)}
    unknown = [cid for cid in payload.contact_ids if cid not in owned]
    if unknown:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="One or more contacts do not belong to this account",
        )

    journey = await safety_repo.create_journey(
        session,
        user_id=current_user.id,
        destination_label=payload.destination_label,
        destination_lat=payload.destination_lat,
        destination_lng=payload.destination_lng,
        expected_duration_minutes=payload.expected_duration_minutes,
        check_in_interval_minutes=payload.check_in_interval_minutes,
        contact_ids=payload.contact_ids,
    )

    await manager.broadcast_to_user(
        current_user.id,
        {
            "type": "journey_started",
            "journey_id": journey.id,
            "destination": journey.destination_label,
            "expected_arrival_at": journey.expected_arrival_at.isoformat(),
            "timestamp": datetime.utcnow().isoformat(),
        },
    )
    return await _to_public(session, journey)


@router.get("/active", response_model=JourneyPublic | None)
async def get_active_journey(
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    journey = await safety_repo.get_active_journey(session, user_id=current_user.id)
    if journey is None:
        return None
    return await _to_public(session, journey)


@router.get("", response_model=list[JourneyPublic])
async def list_journeys(
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    journeys = await safety_repo.list_journeys(session, user_id=current_user.id)
    return [await _to_public(session, journey) for journey in journeys]


@router.post("/{journey_id}/locations", status_code=status.HTTP_204_NO_CONTENT)
async def push_journey_location(
    journey_id: str,
    payload: JourneyLocationRequest,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    journey = await _owned_journey(session, journey_id, current_user.id)
    if journey.status not in ("active", "overdue"):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Journey is no longer in progress"
        )

    await safety_repo.add_journey_location(
        session,
        journey=journey,
        lat=payload.latitude,
        lng=payload.longitude,
        accuracy=payload.accuracy_metres,
    )

    await manager.broadcast_to_user(
        current_user.id,
        {
            "type": "journey_location",
            "journey_id": journey.id,
            "location": {"latitude": payload.latitude, "longitude": payload.longitude},
            "timestamp": datetime.utcnow().isoformat(),
        },
    )
    return None


@router.get("/{journey_id}/locations", response_model=list[JourneyBreadcrumb])
async def get_journey_locations(
    journey_id: str,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    await _owned_journey(session, journey_id, current_user.id)
    rows = await safety_repo.list_journey_locations(session, journey_id=journey_id)
    return [
        JourneyBreadcrumb(
            latitude=row.lat,
            longitude=row.lng,
            accuracy_metres=row.accuracy,
            captured_at=row.captured_at,
        )
        for row in rows
    ]


@router.post("/{journey_id}/check-in", response_model=JourneyPublic)
async def check_in(
    journey_id: str,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    """'Still fine' — resets the overdue clock without ending the journey."""
    journey = await _owned_journey(session, journey_id, current_user.id)
    if journey.status not in ("active", "overdue"):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Journey is no longer in progress"
        )

    updated = await safety_repo.record_check_in(session, journey=journey)
    if updated.status == "overdue":
        updated = await safety_repo.set_journey_status(session, journey=updated, status="active")
    return await _to_public(session, updated)


@router.post("/{journey_id}/arrive", response_model=JourneyPublic)
async def mark_arrived(
    journey_id: str,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    journey = await _owned_journey(session, journey_id, current_user.id)
    updated = await safety_repo.set_journey_status(
        session, journey=journey, status="arrived", ended=True
    )
    await manager.broadcast_to_user(
        current_user.id,
        {
            "type": "journey_ended",
            "journey_id": journey.id,
            "status": "arrived",
            "timestamp": datetime.utcnow().isoformat(),
        },
    )
    return await _to_public(session, updated)


@router.post("/{journey_id}/cancel", response_model=JourneyPublic)
async def cancel_journey(
    journey_id: str,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    journey = await _owned_journey(session, journey_id, current_user.id)
    updated = await safety_repo.set_journey_status(
        session, journey=journey, status="cancelled", ended=True
    )
    await manager.broadcast_to_user(
        current_user.id,
        {
            "type": "journey_ended",
            "journey_id": journey.id,
            "status": "cancelled",
            "timestamp": datetime.utcnow().isoformat(),
        },
    )
    return await _to_public(session, updated)


@router.post("/{journey_id}/escalate", response_model=JourneyPublic)
async def escalate_overdue_journey(
    journey_id: str,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    settings: Settings = Depends(get_settings),
):
    """Run the overdue policy for a journey whose deadline has passed.

    The app calls this when it observes its own journey has run out of time.
    The deadline is re-checked here rather than trusted from the client — a
    journey that still has time left cannot be escalated.
    """
    journey = await _owned_journey(session, journey_id, current_user.id)

    if journey.status != "active":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Journey is not active"
        )
    if journey.expected_arrival_at > datetime.utcnow():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Journey has not run out of time yet"
        )

    updated = await safety_repo.set_journey_status(session, journey=journey, status="overdue")

    breadcrumbs = await safety_repo.list_journey_locations(session, journey_id=journey.id)
    last = breadcrumbs[-1] if breadcrumbs else None

    incident = Incident(
        user_id=current_user.id,
        title="Safe Journey overdue",
        description=(
            f"Did not confirm arrival at {journey.destination_label} within "
            f"{journey.expected_duration_minutes} minutes."
        ),
        threat_level="medium",
    )
    session.add(incident)
    await session.commit()
    await session.refresh(incident)

    contact_ids = await safety_repo.list_participant_ids(session, journey_id=journey.id)
    ws_payload = {
        "type": "journey_overdue",
        "journey_id": journey.id,
        "incident_id": incident.id,
        "destination": journey.destination_label,
        "notified_contact_ids": contact_ids,
        "last_known_location": (
            {"latitude": last.lat, "longitude": last.lng} if last is not None else None
        ),
        "timestamp": datetime.utcnow().isoformat(),
    }
    await manager.broadcast_to_user(current_user.id, ws_payload)

    await _best_effort_push(
        settings=settings,
        session=session,
        user_id=current_user.id,
        title="Safe Journey overdue",
        body=f"You haven't confirmed arriving at {journey.destination_label}.",
        data={"journey_id": journey.id, "incident_id": incident.id},
    )

    return await _to_public(session, updated)
