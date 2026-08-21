import asyncio
import logging
import secrets
from datetime import datetime, timedelta
from typing import Optional

import cloudinary
from cloudinary.utils import api_sign_request
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from fastapi.responses import Response
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.config import Settings, get_settings
from fastapi_app.db import get_session
from fastapi_app.deps import get_evidence_store
from fastapi_app.models import Incident, IncidentShare, Media
from fastapi_app.schemas import UserPublic
from fastapi_app.security import get_current_user
from fastapi_app.services.evidence_store import EvidenceStore, EvidenceStoreError

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/media", tags=["media"])


# Recordings only. An emergency upload is audio or video captured by the
# app, never a document or an archive, so the accepted set is a short
# allow-list rather than anything the client cares to send.
_ALLOWED_EVIDENCE_TYPES = {
    "audio/aac",
    "audio/mp4",
    "audio/mpeg",
    "audio/ogg",
    "audio/wav",
    "audio/webm",
    "video/mp4",
    "video/webm",
}


async def _owned_incident(
    session: AsyncSession, *, incident_id: str, user_id: str
) -> Incident:
    incident = await session.get(Incident, incident_id)
    # Same 404 whether the incident is missing or belongs to someone else:
    # distinguishing them would let anyone probe for valid incident ids.
    if incident is None or incident.user_id != user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found")
    return incident


@router.post("/evidence/{incident_id}", status_code=status.HTTP_201_CREATED)
async def upload_evidence(
    incident_id: str,
    file: UploadFile = File(...),
    notify_contacts: bool = False,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    settings: Settings = Depends(get_settings),
    store: EvidenceStore = Depends(get_evidence_store),
):
    """Stores one evidence recording against an incident, encrypted at rest.

    Returns the id the owner can fetch it back with. No public URL is ever
    minted: a link that leaks must not be enough to play a recording of an
    assault.
    """
    incident = await _owned_incident(
        session, incident_id=incident_id, user_id=current_user.id
    )

    content_type = (file.content_type or "").split(";")[0].strip().lower()
    if content_type not in _ALLOWED_EVIDENCE_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Evidence must be an audio or video recording.",
        )

    # Read with a cap rather than trusting Content-Length, which a client
    # controls. One byte over the limit is enough to reject.
    data = await file.read(settings.evidence_max_size_bytes + 1)
    if len(data) > settings.evidence_max_size_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Recording is too large.",
        )
    if not data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Recording is empty."
        )

    try:
        # Off the event loop: with an object-store backend this is a network
        # round trip of tens of megabytes, and blocking here would stall every
        # other request on the worker -- including someone else's SOS.
        storage_id = await asyncio.to_thread(store.write, data)
    except EvidenceStoreError as exc:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(exc))

    media = Media(
        incident_id=incident.id,
        # Not a URL despite the column name: an internal reference the
        # retrieval endpoint resolves. The column predates this feature.
        url=storage_id,
        media_type=content_type,
        size_bytes=len(data),
    )
    session.add(media)
    await session.commit()
    await session.refresh(media)

    followup = {"contacts_notified": 0, "share_expires_at": None}
    if notify_contacts:
        followup = await _send_evidence_followup(
            session=session, settings=settings, user_id=current_user.id, incident=incident
        )

    return {
        "id": media.id,
        "incident_id": incident.id,
        "media_type": media.media_type,
        "size_bytes": media.size_bytes,
        "created_at": media.created_at,
        # FR-EMG-05's evidence URL, delivered as a follow-up rather than in
        # the alert itself -- see services/emergency_dispatch.py for why.
        "followup": followup,
    }


async def _send_evidence_followup(
    *, session: AsyncSession, settings: Settings, user_id: str, incident: Incident
) -> dict:
    """Mints a share link for the incident and emails it to the contacts.

    Failures are swallowed into the response rather than raised: the
    recording is already stored, and losing an upload because a follow-up
    email bounced would be the wrong trade entirely.
    """
    from fastapi_app.models import User
    from fastapi_app.routers.shares import DEFAULT_SHARE_DAYS, _hash_token, _utcnow
    from fastapi_app.services.emergency_dispatch import send_evidence_followup

    try:
        token = secrets.token_urlsafe(32)
        share = IncidentShare(
            incident_id=incident.id,
            token_hash=_hash_token(token),
            expires_at=_utcnow() + timedelta(days=DEFAULT_SHARE_DAYS),
        )
        session.add(share)
        await session.commit()
        await session.refresh(share)

        owner = await session.get(User, user_id)
        report = await send_evidence_followup(
            session=session,
            settings=settings,
            user=owner,
            incident_id=incident.id,
            share_url=f"{settings.public_base_url.rstrip('/')}/share/{token}",
        )
        return {
            "contacts_notified": report.contacts_notified,
            "share_expires_at": share.expires_at,
        }
    except Exception as exc:  # noqa: BLE001 - never lose a stored recording
        logger.warning("Evidence follow-up failed for incident %s: %s", incident.id, exc)
        return {"contacts_notified": 0, "share_expires_at": None}


@router.get("/evidence/{media_id}")
async def download_evidence(
    media_id: str,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    store: EvidenceStore = Depends(get_evidence_store),
):
    """Streams one recording back to the person it belongs to."""
    media = await session.get(Media, media_id)
    if media is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Evidence not found")

    await _owned_incident(session, incident_id=media.incident_id, user_id=current_user.id)

    try:
        data = await asyncio.to_thread(store.read, media.url)
    except EvidenceStoreError as exc:
        raise HTTPException(status_code=status.HTTP_410_GONE, detail=str(exc))

    return Response(
        content=data,
        media_type=media.media_type,
        headers={
            # Never rendered inline and never cached by an intermediary.
            "Content-Disposition": f'attachment; filename="evidence-{media.id}"',
            "Cache-Control": "no-store, private",
        },
    )


@router.get("/evidence/incident/{incident_id}/list")
async def list_incident_evidence(
    incident_id: str,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    await _owned_incident(session, incident_id=incident_id, user_id=current_user.id)
    rows = (
        (
            await session.execute(
                select(Media).where(Media.incident_id == incident_id).order_by(Media.created_at)
            )
        )
        .scalars()
        .all()
    )
    return [
        {
            "id": row.id,
            "media_type": row.media_type,
            "size_bytes": row.size_bytes,
            "created_at": row.created_at,
        }
        for row in rows
    ]


class SignUploadRequest(BaseModel):
    folder: str = Field(default="evidence", description="Cloudinary folder to store uploads")
    public_id: Optional[str] = Field(default=None, description="Optional public_id to control filename")
    resource_type: str = Field(default="auto", description="Cloudinary resource type (image, video, raw, auto)")


@router.post("/sign-upload")
async def sign_upload(
    payload: SignUploadRequest,
    settings: Settings = Depends(get_settings),
    current_user: UserPublic = Depends(get_current_user),
):
    if not (settings.cloudinary_cloud_name and settings.cloudinary_api_key and settings.cloudinary_api_secret):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cloudinary is not configured")

    allowed_resource_types = {"image", "video", "raw", "auto"}
    if payload.resource_type not in allowed_resource_types:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid resource_type")

    if ".." in payload.folder:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid folder name")

    cloudinary.config(
        cloud_name=settings.cloudinary_cloud_name,
        api_key=settings.cloudinary_api_key,
        api_secret=settings.cloudinary_api_secret,
        secure=True,
    )

    timestamp = int(datetime.utcnow().timestamp())
    params = {
        "timestamp": timestamp,
        "folder": payload.folder,
    }
    if payload.public_id:
        params["public_id"] = payload.public_id

    signature = api_sign_request(params, settings.cloudinary_api_secret)
    upload_url = f"https://api.cloudinary.com/v1_1/{settings.cloudinary_cloud_name}/{payload.resource_type}/upload"

    return {
        "cloud_name": settings.cloudinary_cloud_name,
        "api_key": settings.cloudinary_api_key,
        "signature": signature,
        "timestamp": timestamp,
        "folder": payload.folder,
        "public_id": payload.public_id,
        "upload_url": upload_url,
        "resource_type": payload.resource_type,
    }
