"""Time-limited, revocable read-only links to an incident — SRS FR-RPT-06.

A report that cannot leave the phone is of limited use to the people who
act on it. This is how an incident reaches someone with no SafeHer account
— a police officer, a lawyer, a parent — without handing them the owner's
credentials.

The security posture is deliberately narrow:

* **The token is the only credential**, so it is 32 bytes of `secrets`
  randomness, shown once, and stored only as a hash.
* **It expires**, seven days by default per the SRS, and can be revoked
  sooner.
* **It is read-only and minimal.** The shared view carries the incident, its
  location and its evidence — not the owner's email, phone, contacts or any
  other incident.
* **Evidence still streams through the server**, decrypted per request. A
  share link never turns into a permanent public URL for a recording.
"""

from __future__ import annotations

import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import Response
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.config import Settings, get_settings
from fastapi_app.db import get_session
from fastapi_app.deps import get_evidence_store
from fastapi_app.models import Incident, IncidentShare, Location, Media
from fastapi_app.schemas import UserPublic
from fastapi_app.security import get_current_user
from fastapi_app.services.evidence_store import EvidenceStore, EvidenceStoreError

router = APIRouter(prefix="/api/v1", tags=["shares"])

DEFAULT_SHARE_DAYS = 7
MAX_SHARE_DAYS = 30


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _hash_token(token: str) -> str:
    """SHA-256, not a password hash.

    A share token is 256 bits of randomness, so it needs no work factor to
    resist guessing — and unlike a password it is looked up on every
    unauthenticated read, where a deliberately slow hash would be a free
    denial-of-service lever.
    """
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


async def _resolve_share(session: AsyncSession, token: str) -> IncidentShare:
    share = (
        (
            await session.execute(
                select(IncidentShare).where(IncidentShare.token_hash == _hash_token(token))
            )
        )
        .scalars()
        .first()
    )
    # One message for unknown, revoked and expired alike. Distinguishing
    # them would confirm to a stranger that a link was once real, which is
    # itself information about someone's incident.
    if share is None or share.revoked_at is not None or _utcnow() > share.expires_at:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="This link is not valid. It may have expired or been revoked.",
        )
    return share


@router.post("/incidents/{incident_id}/share", status_code=status.HTTP_201_CREATED)
async def create_share(
    incident_id: str,
    days: int = DEFAULT_SHARE_DAYS,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    """Mints a share link. The token is returned once and never again."""
    incident = await session.get(Incident, incident_id)
    if incident is None or incident.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found")

    if days < 1 or days > MAX_SHARE_DAYS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"A link can last between 1 and {MAX_SHARE_DAYS} days.",
        )

    token = secrets.token_urlsafe(32)
    share = IncidentShare(
        incident_id=incident.id,
        token_hash=_hash_token(token),
        expires_at=_utcnow() + timedelta(days=days),
    )
    session.add(share)
    await session.commit()
    await session.refresh(share)

    return {
        "id": share.id,
        # Shown once. Only the hash is stored, so this cannot be recovered
        # later — losing it means minting a new link, which is the correct
        # trade for a credential that needs no password to use.
        "token": token,
        "expires_at": share.expires_at,
    }


@router.get("/incidents/{incident_id}/shares")
async def list_shares(
    incident_id: str,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    incident = await session.get(Incident, incident_id)
    if incident is None or incident.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found")

    rows = (
        (
            await session.execute(
                select(IncidentShare)
                .where(IncidentShare.incident_id == incident_id)
                .order_by(IncidentShare.created_at.desc())
            )
        )
        .scalars()
        .all()
    )
    now = _utcnow()
    return [
        {
            "id": row.id,
            "expires_at": row.expires_at,
            "revoked_at": row.revoked_at,
            "active": row.revoked_at is None and row.expires_at > now,
        }
        for row in rows
    ]


@router.delete("/incidents/{incident_id}/shares/{share_id}", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_share(
    incident_id: str,
    share_id: str,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    incident = await session.get(Incident, incident_id)
    if incident is None or incident.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found")

    share = await session.get(IncidentShare, share_id)
    if share is None or share.incident_id != incident_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Link not found")

    if share.revoked_at is None:
        share.revoked_at = _utcnow()
        await session.commit()
    return None


# --------------------------------------------------------------------------
# Unauthenticated, token-only reads.
# --------------------------------------------------------------------------


@router.get("/share/{token}")
async def view_shared_incident(
    token: str,
    session: AsyncSession = Depends(get_session),
):
    """The shared report. Deliberately minimal about who it belongs to."""
    share = await _resolve_share(session, token)
    incident = await session.get(Incident, share.incident_id)
    if incident is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="This link is not valid.")

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
    evidence = (
        (
            await session.execute(
                select(Media).where(Media.incident_id == incident.id).order_by(Media.created_at)
            )
        )
        .scalars()
        .all()
    )

    return {
        "incident": {
            "title": incident.title,
            "description": incident.description,
            "threat_level": incident.threat_level,
            "created_at": incident.created_at,
        },
        # The owner's identity, contacts and other incidents are all absent
        # on purpose: whoever holds this link needs the incident, not the
        # person's account.
        "location": (
            {"latitude": location.lat, "longitude": location.lng, "accuracy": location.accuracy}
            if location
            else None
        ),
        "evidence": [
            {"id": row.id, "media_type": row.media_type, "size_bytes": row.size_bytes}
            for row in evidence
        ],
        "expires_at": share.expires_at,
    }


@router.get("/share/{token}/evidence/{media_id}")
async def download_shared_evidence(
    token: str,
    media_id: str,
    session: AsyncSession = Depends(get_session),
    store: EvidenceStore = Depends(get_evidence_store),
):
    """Streams one recording to a link holder.

    Decrypted per request rather than exposed as a file: revoking the link
    or letting it expire has to actually stop access, which it cannot do if
    a permanent URL was handed out along the way.
    """
    share = await _resolve_share(session, token)

    media = await session.get(Media, media_id)
    if media is None or media.incident_id != share.incident_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Evidence not found")

    try:
        data = store.read(media.url)
    except EvidenceStoreError as exc:
        raise HTTPException(status_code=status.HTTP_410_GONE, detail=str(exc))

    return Response(
        content=data,
        media_type=media.media_type,
        headers={
            "Content-Disposition": f'attachment; filename="evidence-{media.id}"',
            "Cache-Control": "no-store, private",
        },
    )
