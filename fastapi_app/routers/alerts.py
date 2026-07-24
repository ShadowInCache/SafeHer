from datetime import datetime
from typing import Any

from fastapi import APIRouter, Depends, status
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.config import Settings, get_settings
from fastapi_app.db import get_session
from fastapi_app.models import Incident, Location
from fastapi_app.realtime import manager
from fastapi_app.repositories import fcm_tokens
from fastapi_app.schemas import (
    EmergencyAlertRequest,
    HeartbeatRequest,
    IncidentPublic,
    ProcessThreatRequest,
    UserPublic,
)
from fastapi_app.security import get_current_user
from fastapi_app.services.notifications import send_fcm_notification
from fastapi_app.services.processor_client import process_threat

router = APIRouter(prefix="/api/v1/alerts", tags=["alerts"])

_latest_scores: dict[str, dict[str, Any]] = {}


def _to_level(score: float) -> str:
    if score >= 80:
        return "critical"
    if score >= 60:
        return "high"
    if score >= 35:
        return "medium"
    return "low"


async def _best_effort_push(
    *,
    settings: Settings,
    session: AsyncSession,
    user_id: str,
    title: str,
    body: str,
    data: dict[str, Any],
) -> None:
    if not settings.fcm_server_key:
        return

    tokens = await fcm_tokens.list_by_user(session, user_id=user_id)
    for item in tokens:
        try:
            await send_fcm_notification(
                server_key=settings.fcm_server_key,
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


@router.post("/process-threat")
async def process_threat_alert(
    payload: ProcessThreatRequest,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    settings: Settings = Depends(get_settings),
):
    processor_input = {
        "device_id": payload.device_id,
        "user_id": current_user.id,
        "type": payload.threat_type,
        "data": payload.details,
        "location": payload.location,
    }
    processor_result = await process_threat(settings, processor_input)

    processor_confidence = float(processor_result.get("confidence", payload.confidence))
    threat_detected = bool(processor_result.get("threat_detected", processor_confidence >= 0.5))

    if threat_detected:
        level = str(processor_result.get("threat_level") or _to_level(processor_confidence * 100))
        incident = Incident(
            user_id=current_user.id,
            title=f"{payload.threat_type.title()} threat detected",
            description=payload.summary,
            threat_level=level,
            evidence_url=processor_result.get("evidence_url"),
        )
        session.add(incident)
        await session.commit()
        await session.refresh(incident)

        ws_payload = {
            "type": "threat_alert",
            "incident_id": incident.id,
            "threat_type": payload.threat_type,
            "threat_level": level,
            "confidence": processor_confidence,
            "summary": payload.summary,
            "timestamp": datetime.utcnow().isoformat(),
        }
        await manager.broadcast_to_user(current_user.id, ws_payload)

        await _best_effort_push(
            settings=settings,
            session=session,
            user_id=current_user.id,
            title="SafeHer Alert",
            body=payload.summary,
            data={"incident_id": incident.id, "threat_level": level},
        )

    _latest_scores[current_user.id] = {
        "score": round(processor_confidence * 100, 2),
        "level": _to_level(processor_confidence * 100),
        "updated_at": datetime.utcnow().isoformat(),
    }

    return {
        "processor": processor_result,
        "threat_detected": threat_detected,
        "live_score": _latest_scores[current_user.id],
    }


@router.post("/emergency", status_code=status.HTTP_201_CREATED, response_model=IncidentPublic)
async def trigger_emergency_alert(
    payload: EmergencyAlertRequest,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    settings: Settings = Depends(get_settings),
):
    incident = Incident(
        user_id=current_user.id,
        title="Emergency SOS",
        description=payload.summary,
        threat_level=payload.severity,
        evidence_url=None,
    )
    session.add(incident)

    loc = payload.location or {}
    location = Location(
        user_id=current_user.id,
        device_id=None,
        lat=float(loc.get("latitude", 0.0)),
        lng=float(loc.get("longitude", 0.0)),
        accuracy=float(loc.get("accuracy", 0.0)) if "accuracy" in loc else None,
    )
    session.add(location)

    await session.commit()
    await session.refresh(incident)

    ws_payload = {
        "type": "emergency_alert",
        "incident_id": incident.id,
        "severity": payload.severity,
        "summary": payload.summary,
        "location": payload.location,
        "auto": payload.auto,
        "timestamp": datetime.utcnow().isoformat(),
    }
    await manager.broadcast_to_user(current_user.id, ws_payload)

    await _best_effort_push(
        settings=settings,
        session=session,
        user_id=current_user.id,
        title="Emergency SOS Triggered",
        body=payload.summary,
        data={"incident_id": incident.id, "severity": payload.severity},
    )

    _latest_scores[current_user.id] = {
        "score": 100.0,
        "level": "critical",
        "updated_at": datetime.utcnow().isoformat(),
    }

    return incident


@router.post("/heartbeat", status_code=status.HTTP_202_ACCEPTED)
async def submit_heartbeat(
    payload: HeartbeatRequest,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    location = payload.location
    lat = float(location.get("latitude", 0.0))
    lng = float(location.get("longitude", 0.0))

    session.add(
        Location(
            user_id=current_user.id,
            device_id=None,
            lat=lat,
            lng=lng,
            accuracy=float(location.get("accuracy", 0.0)) if "accuracy" in location else None,
        )
    )
    await session.commit()

    level = _to_level(payload.threat_score)
    _latest_scores[current_user.id] = {
        "score": round(payload.threat_score, 2),
        "level": level,
        "updated_at": payload.timestamp.isoformat(),
    }

    return {"status": "accepted", "score": payload.threat_score, "level": level}


@router.get("/live")
async def get_live_alert_state(
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    latest = _latest_scores.get(current_user.id, {"score": 0.0, "level": "low", "updated_at": None})

    rows = await session.execute(
        select(Incident)
        .where(Incident.user_id == current_user.id)
        .order_by(desc(Incident.created_at))
        .limit(5)
    )
    incidents = rows.scalars().all()

    return {
        "live_score": latest,
        "recent_incidents": [
            {
                "id": item.id,
                "title": item.title,
                "threat_level": item.threat_level,
                "created_at": item.created_at,
            }
            for item in incidents
        ],
    }
