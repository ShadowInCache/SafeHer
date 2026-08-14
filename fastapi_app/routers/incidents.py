from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.db import get_session
from fastapi_app.models import Incident, Location, Media
from fastapi_app.schemas import IncidentCreate, IncidentPublic, UserPublic
from fastapi_app.security import get_current_user
from fastapi_app.services.notifications import send_fcm_notification
from fastapi_app.config import get_settings

router = APIRouter(prefix="/api/v1/incidents", tags=["incidents"])


def _with_location(incident: Incident, location: Location | None) -> IncidentPublic:
    public = IncidentPublic.model_validate(incident)
    if location is not None:
        public.latitude = location.lat
        public.longitude = location.lng
        public.location_accuracy = location.accuracy
    return public


@router.post("/", response_model=IncidentPublic, status_code=status.HTTP_201_CREATED)
async def create_incident(
    payload: IncidentCreate,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    incident = Incident(
        user_id=current_user.id,
        title=payload.title,
        description=payload.description,
        threat_level=payload.threat_level,
        evidence_url=payload.evidence_url,
    )
    session.add(incident)
    await session.commit()
    await session.refresh(incident)

    if payload.evidence_url:
        media = Media(
            incident_id=incident.id,
            url=payload.evidence_url,
            media_type=payload.media_type or "unknown",
            size_bytes=payload.media_size_bytes,
        )
        session.add(media)
        await session.commit()

    # Optional FCM push
    if payload.fcm_token:
        settings = get_settings()
        try:
            await send_fcm_notification(
                server_key=settings.fcm_server_key,
                token=payload.fcm_token,
                title=payload.title,
                body=payload.description or "New incident reported",
                data={"incident_id": incident.id, "threat_level": payload.threat_level},
                session=session,
                user_id=current_user.id,
            )
        except HTTPException:
            # Do not fail the incident creation if notification fails
            pass

    return incident


@router.get("/", response_model=list[IncidentPublic])
async def list_incidents(
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    result = await session.execute(
        select(Incident)
        .where(Incident.user_id == current_user.id)
        .order_by(desc(Incident.created_at))
        .limit(limit)
        .offset(offset)
    )
    rows = result.scalars().all()
    if not rows:
        return []

    incident_ids = [row.id for row in rows]
    locations = (
        (await session.execute(select(Location).where(Location.incident_id.in_(incident_ids))))
        .scalars()
        .all()
    )
    location_by_incident = {loc.incident_id: loc for loc in locations}
    return [_with_location(row, location_by_incident.get(row.id)) for row in rows]


@router.get("/{incident_id}", response_model=IncidentPublic)
async def get_incident(
    incident_id: str,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    incident = await session.get(Incident, incident_id)
    if not incident or incident.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found")
    location = (
        await session.execute(select(Location).where(Location.incident_id == incident_id))
    ).scalar_one_or_none()
    return _with_location(incident, location)
