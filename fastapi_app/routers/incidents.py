from datetime import datetime
from fastapi.responses import Response
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.db import get_session
from fastapi_app.deps import get_evidence_store
from fastapi_app.models import Incident, Location, Media
from fastapi_app.schemas import IncidentCreate, IncidentPublic, UserPublic
from fastapi_app.security import get_current_user
from fastapi_app.services.evidence_store import EvidenceStore, EvidenceStoreError
from fastapi_app.services.incident_pdf import build_incident_pdf
from fastapi_app.services.incident_summary import (
    IncidentSummarizer,
    SummaryGenerationError,
    SummaryNotConfigured,
    build_prompt,
)
from fastapi_app.services.notifications import send_fcm_notification
from fastapi_app.config import Settings, get_settings

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


@router.get("/{incident_id}/report.pdf")
async def export_incident_pdf(
    incident_id: str,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    store: EvidenceStore = Depends(get_evidence_store),
):
    """Forensic incident report (SRS FR-RPT-03).

    Evidence is decrypted here only to hash it -- the recording itself never
    enters the PDF. A report is routinely forwarded to people who should see
    the summary rather than hear the audio, and the hash is what lets them
    verify a copy they are given separately.
    """
    incident = await session.get(Incident, incident_id)
    if incident is None or incident.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found")

    location = (
        (
            await session.execute(
                select(Location)
                .where(Location.incident_id == incident.id)
                .order_by(Location.captured_at)
            )
        )
        .scalars()
        .first()
    )
    media_rows = (
        (
            await session.execute(
                select(Media).where(Media.incident_id == incident.id).order_by(Media.created_at)
            )
        )
        .scalars()
        .all()
    )

    evidence = []
    for row in media_rows:
        try:
            evidence.append((row.id, row.media_type, store.read(row.url)))
        except EvidenceStoreError:
            # A recording that cannot be read is omitted rather than faked
            # with a placeholder hash -- a chain of custody with an invented
            # link in it is worse than one that is honestly short.
            continue

    pdf = build_incident_pdf(
        incident_title=incident.title,
        incident_description=incident.description,
        threat_level=incident.threat_level,
        occurred_at=incident.created_at,
        reported_by=current_user.full_name or current_user.email,
        latitude=location.lat if location else None,
        longitude=location.lng if location else None,
        evidence=evidence,
        ai_summary=incident.ai_summary,
    )

    return Response(
        content=pdf,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="safeher-incident-{incident.id}.pdf"',
            "Cache-Control": "no-store, private",
        },
    )


@router.post("/{incident_id}/summary")
async def generate_incident_summary(
    incident_id: str,
    force: bool = False,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    settings: Settings = Depends(get_settings),
):
    """Writes a plain-language summary of the incident (SRS FR-RPT-01).

    Cached after the first run: a summary whose wording changes every time
    the report is opened is not something anyone can cite, and regenerating
    on every read would spend the free tier on nothing. `force=true` rewrites
    it, which is what the client uses once evidence has finished uploading
    and the fact sheet is finally complete.
    """
    incident = await session.get(Incident, incident_id)
    if incident is None or incident.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found")

    if incident.ai_summary and not force:
        return {
            "summary": incident.ai_summary,
            "generated_at": incident.ai_summary_generated_at,
            "regenerated": False,
        }

    summarizer = IncidentSummarizer(
        api_key=settings.gemini_api_key, model=settings.gemini_model
    )
    if not summarizer.is_configured:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Summaries are not available: no model is configured.",
        )

    location = (
        (
            await session.execute(
                select(Location)
                .where(Location.incident_id == incident.id)
                .order_by(Location.captured_at)
            )
        )
        .scalars()
        .first()
    )
    evidence_count = len(
        (
            await session.execute(select(Media).where(Media.incident_id == incident.id))
        )
        .scalars()
        .all()
    )

    prompt = build_prompt(
        title=incident.title,
        severity=incident.threat_level,
        occurred_at=incident.created_at.isoformat(),
        latitude=location.lat if location else None,
        longitude=location.lng if location else None,
        evidence_count=evidence_count,
        contacts_notified=None,
        trigger=incident.description or "not recorded",
    )

    try:
        summary = await summarizer.summarise(prompt)
    except SummaryNotConfigured as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc))
    except SummaryGenerationError as exc:
        # No summary rather than a guessed one: this text sits at the top of
        # a report and will be read as a record of events.
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc))

    incident.ai_summary = summary
    incident.ai_summary_generated_at = datetime.utcnow()
    await session.commit()

    return {
        "summary": summary,
        "generated_at": incident.ai_summary_generated_at,
        "regenerated": True,
    }
