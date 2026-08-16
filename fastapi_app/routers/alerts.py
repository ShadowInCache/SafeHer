import logging
from datetime import datetime
from typing import Any, Optional
from uuid import uuid4

from fastapi import APIRouter, Depends, status
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.config import Settings, get_settings
from fastapi_app.db import get_session
from fastapi_app.deps import fcm_credentials
from fastapi_app.models import Incident, Location, User
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
from fastapi_app.services import threat_fusion
from fastapi_app.services.emergency_dispatch import dispatch_to_contacts
from fastapi_app.services.notifications import send_fcm_notification
from fastapi_app.services.processor_client import process_threat

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/alerts", tags=["alerts"])

_latest_scores: dict[str, dict[str, Any]] = {}

# SRS §6.2 smoothing needs the previous smoothed value. In memory, like
# `_latest_scores`: losing it on restart costs one unsmoothed reading, which
# errs towards raising an alarm rather than missing one. The deduplication
# window is deliberately *not* kept here -- that one is read from the
# database, because forgetting it would mean alerting every contact twice.
_smoothed_scores: dict[str, float] = {}


async def _auto_dispatch_if_threatened(
    *,
    session: AsyncSession,
    settings: Settings,
    user_id: str,
    raw_score: float,
    incident: Optional[Incident] = None,
    weapon_confidence: float = 0.0,
) -> dict[str, Any]:
    """SRS FR-EMG-02 -- raise the alarm without being asked.

    Until this existed, a detected threat pushed a notification to the
    user's *own* phone and stopped there. Her emergency contacts were never
    told unless she pressed SOS herself, which is precisely the case
    FR-EMG-02 covers: the situations where she cannot.
    """
    owner = await session.get(User, user_id)
    if owner is None:
        return {"triggered": False, "reason": "no such user"}

    threshold = getattr(owner, "threat_threshold", None) or threat_fusion.DEFAULT_THREAT_THRESHOLD

    # The window is measured from the last alert SafeHer raised by itself.
    # A manual SOS is deliberately not counted: if she pressed the button
    # after an automatic alert, that is a second, deliberate call for help.
    last_auto = await session.scalar(
        select(Incident.created_at)
        .where(Incident.user_id == user_id, Incident.auto_dispatched.is_(True))
        .order_by(Incident.created_at.desc())
        .limit(1)
    )

    decision = threat_fusion.evaluate(
        raw_score=raw_score,
        previous_smoothed=_smoothed_scores.get(user_id),
        threshold=threshold,
        weapon_confidence=weapon_confidence,
        last_alert_at=last_auto,
    )
    _smoothed_scores[user_id] = decision.smoothed_score

    if not decision.should_trigger:
        if decision.suppressed_by_dedup:
            logger.info("Auto-SOS suppressed for %s: %s", user_id, decision.reason)
        return {
            "triggered": False,
            "reason": decision.reason,
            "score": round(decision.boosted_score, 3),
            "threshold": threshold,
        }

    if incident is None:
        incident = Incident(
            user_id=user_id,
            title="Automatic SOS",
            description=(
                "Raised automatically by SafeHer: " + decision.reason
            ),
            threat_level="critical",
        )
        session.add(incident)

    incident.auto_dispatched = True
    session.add(incident)
    await session.commit()
    await session.refresh(incident)

    logger.warning("Auto-SOS dispatched for %s: %s", user_id, decision.reason)
    report = await dispatch_to_contacts(
        session=session,
        settings=settings,
        user=owner,
        incident_id=incident.id,
        evidence_url=incident.evidence_url,
    )
    return {
        "triggered": True,
        "reason": decision.reason,
        "score": round(decision.boosted_score, 3),
        "threshold": threshold,
        "incident_id": incident.id,
        "contacts_notified": report.contacts_notified,
    }


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

    # SRS FR-EMG-02. The push above reaches the user's own phone, which is
    # no help if she cannot look at it -- this is what reaches the people
    # who can come. `processor_confidence` is already on §6.2's 0-1 scale.
    auto_sos = await _auto_dispatch_if_threatened(
        session=session,
        settings=settings,
        user_id=current_user.id,
        raw_score=processor_confidence,
        incident=incident if threat_detected else None,
        weapon_confidence=float(processor_result.get("weapon_confidence", 0.0) or 0.0),
    )

    return {
        "processor": processor_result,
        "threat_detected": threat_detected,
        "live_score": _latest_scores[current_user.id],
        "auto_sos": auto_sos,
    }


@router.get("/channels")
async def get_alert_channels(
    current_user: UserPublic = Depends(get_current_user),
    settings: Settings = Depends(get_settings),
):
    """Which emergency channels this deployment can actually deliver on.

    The app needs this to tell the truth in the contacts screen. A contact
    with only a phone number is unreachable when SMS is unconfigured, and
    the client has no other way to know that — it would otherwise show a
    saved contact as ready and let a user believe her sister will be called.

    `email_requires_address` states the consequence plainly so the client
    does not have to re-derive the rule.
    """
    sms_configured = bool(
        settings.twilio_account_sid and settings.twilio_auth_token and settings.twilio_from_number
    )
    email_configured = bool(settings.smtp_configured) or bool(
        settings.onesignal_app_id and settings.onesignal_api_key
    )

    return {
        "sms": sms_configured,
        "email": email_configured,
        "push": fcm_credentials(settings).is_configured,
        # True when email is the only channel that can reach an ordinary
        # contact, so a contact without an address cannot be reached at all.
        "email_requires_address": email_configured and not sms_configured,
    }


@router.post("/emergency", status_code=status.HTTP_201_CREATED, response_model=IncidentPublic)
async def trigger_emergency_alert(
    payload: EmergencyAlertRequest,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    settings: Settings = Depends(get_settings),
):
    incident_id = str(uuid4())
    incident = Incident(
        id=incident_id,
        user_id=current_user.id,
        title="Emergency SOS",
        description=payload.summary,
        threat_level=payload.severity,
        evidence_url=None,
    )
    session.add(incident)

    loc = payload.location or {}
    has_location = "latitude" in loc and "longitude" in loc
    if has_location:
        location = Location(
            user_id=current_user.id,
            device_id=None,
            incident_id=incident_id,
            lat=float(loc["latitude"]),
            lng=float(loc["longitude"]),
            accuracy=float(loc["accuracy"]) if "accuracy" in loc else None,
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

    # FR-EMG-04/05: notify the people who can actually help. Everything
    # above this line only told the user's own devices about an emergency
    # they already know they are in.
    #
    # The incident is committed before this runs, so a dispatch that fails
    # wholesale still leaves a durable record to retry from, and the caller
    # still gets a 201 rather than an error that would make the app think
    # the SOS never landed.
    owner = await session.get(User, current_user.id)
    dispatch = await dispatch_to_contacts(
        session=session,
        settings=settings,
        user=owner,
        incident_id=incident.id,
        latitude=float(loc["latitude"]) if has_location else None,
        longitude=float(loc["longitude"]) if has_location else None,
        evidence_url=incident.evidence_url,
    )

    response = IncidentPublic.model_validate(incident)
    if has_location:
        response.latitude = float(loc["latitude"])
        response.longitude = float(loc["longitude"])
        response.location_accuracy = float(loc["accuracy"]) if "accuracy" in loc else None
    response.contacts_total = dispatch.contacts_total
    response.contacts_notified = dispatch.contacts_notified
    response.contacts_reached = dispatch.reached_contact_ids
    return response


@router.post("/heartbeat", status_code=status.HTTP_202_ACCEPTED)
async def submit_heartbeat(
    payload: HeartbeatRequest,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    settings: Settings = Depends(get_settings),
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

    # SRS FR-EMG-02, for when firmware exists to post these. `threat_score`
    # is validated 0-100 on this endpoint while §6.2 works in 0-1, so it is
    # normalised here rather than letting a 100 read as far above threshold
    # and a 0.8 read as far below it.
    auto_sos = await _auto_dispatch_if_threatened(
        session=session,
        settings=settings,
        user_id=current_user.id,
        raw_score=payload.threat_score / 100.0,
    )

    return {
        "status": "accepted",
        "score": payload.threat_score,
        "level": level,
        "auto_sos": auto_sos,
    }


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
