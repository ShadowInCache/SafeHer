import json
import logging
from datetime import datetime
from typing import Any, Optional
from uuid import uuid4

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    File,
    HTTPException,
    UploadFile,
    status,
)
from fastapi.concurrency import run_in_threadpool
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.config import Settings, get_settings
from fastapi_app.db import get_session
from fastapi_app.deps import fcm_credentials
from fastapi_app.models import Incident, Location, User
from fastapi_app.realtime import manager
from fastapi_app.repositories import emergency_contacts as contacts_repo
from fastapi_app.repositories import fcm_tokens
from fastapi_app.schemas import (
    EmergencyAlertRequest,
    HeartbeatRequest,
    IncidentPublic,
    ModelScoresRequest,
    ProcessThreatRequest,
    UserPublic,
)
from fastapi_app.security import get_current_user
from fastapi_app.services import threat_fusion, threat_models, weapon_detector
from fastapi_app.services.emergency_dispatch import (
    DISPATCH_COMPLETE,
    DISPATCH_IN_PROGRESS,
    dispatch_to_contacts,
    run_dispatch_in_background,
)
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
# The banded level each user was last in. Held only so `level_for` can apply
# hysteresis on the way down; losing it on restart costs one un-damped band
# transition, never a missed alarm.
_threat_levels: dict[str, 'threat_fusion.ThreatLevel'] = {}


async def _auto_dispatch_if_threatened(
    *,
    background_tasks: Optional[BackgroundTasks] = None,
    session: AsyncSession,
    settings: Settings,
    user_id: str,
    raw_score: float,
    incident: Optional[Incident] = None,
    weapon_confidence: float = 0.0,
    in_high_risk_zone: bool = False,
    scores: Optional[threat_models.ModalityScores] = None,
    weapon_label: Optional[str] = None,
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

    # `raw_score` arrives already fused by the caller, so it is handed back
    # in as the glove signal alone: fusing an already-fused number against
    # itself would double-count it. `weapon_confidence` and
    # `in_high_risk_zone` are no longer inputs to the score -- see the module
    # doc in `threat_fusion` for why context was removed -- and are recorded
    # on the incident as supporting evidence instead.
    decision = threat_fusion.evaluate(
        signals=threat_fusion.ThreatSignals(glove=raw_score),
        previous_smoothed=_smoothed_scores.get(user_id),
        previous_level=_threat_levels.get(user_id),
        threshold=threshold,
        last_alert_at=last_auto,
    )
    if decision is None:
        return {"triggered": False, "reason": "no signal reported"}
    _smoothed_scores[user_id] = decision.smoothed_score
    _threat_levels[user_id] = decision.level

    if not decision.should_trigger:
        if decision.suppressed_by_dedup:
            logger.info("Auto-SOS suppressed for %s: %s", user_id, decision.reason)
        return {
            "triggered": False,
            "reason": decision.reason,
            "score": round(decision.smoothed_score, 3),
            "threshold": threshold,
        }

    if incident is None:
        findings = (
            threat_models.describe(scores, weapon_label=weapon_label)
            if scores is not None
            else decision.reason
        )
        incident = Incident(
            user_id=user_id,
            title="Automatic SOS",
            # The findings, not the arithmetic. "A knife was detected in
            # view" is what she needs to read first; the score is recorded
            # alongside for anyone who wants to audit the decision.
            description=findings,
            threat_level="critical",
        )
        session.add(incident)

    incident.auto_dispatched = True
    # What the models observed, recorded on the incident itself. Without this
    # the report can say SafeHer raised the alarm but not why, which is no
    # use to the woman reading it and worthless as evidence.
    if scores is not None:
        incident.motion_score = scores.motion
        incident.audio_score = scores.audio
        incident.vision_score = scores.vision
        incident.weapon_confidence = scores.weapon_confidence or None
        incident.detections = threat_models.describe(scores, weapon_label=weapon_label)
    incident.fused_score = round(decision.smoothed_score, 4)
    incident.threshold_used = threshold
    session.add(incident)
    await session.commit()
    await session.refresh(incident)

    logger.warning("Auto-SOS dispatched for %s: %s", user_id, decision.reason)

    contacts = await contacts_repo.list_by_user(session, user_id=user_id)
    incident.dispatch_status = DISPATCH_IN_PROGRESS
    incident.contacts_total = len(contacts)
    incident.contacts_notified = 0
    incident.contacts_reached = json.dumps([])
    incident.contacts_failed = json.dumps([])
    await session.commit()

    if background_tasks is not None:
        # Same reasoning as the manual SOS: a fan-out that can take minutes
        # against a blocked channel must not be inside the request. An
        # automatic alert has *no* countdown absorbing the wait, so this
        # matters more here, not less.
        background_tasks.add_task(
            run_dispatch_in_background,
            settings=settings,
            user_id=user_id,
            incident_id=incident.id,
            evidence_url=incident.evidence_url,
        )
        notified = None
    else:
        # No background queue available (a direct internal call, or a test
        # driving this helper). Run inline rather than silently not alerting
        # anyone -- slow is survivable here, skipped is not.
        report = await dispatch_to_contacts(
            session=session,
            settings=settings,
            user=owner,
            incident_id=incident.id,
            evidence_url=incident.evidence_url,
        )
        incident.dispatch_status = DISPATCH_COMPLETE
        incident.contacts_notified = report.contacts_notified
        incident.contacts_reached = json.dumps(report.reached_contact_ids)
        incident.contacts_failed = json.dumps(report.failed_contact_ids)
        incident.dispatch_completed_at = datetime.utcnow()
        await session.commit()
        notified = report.contacts_notified

    return {
        "triggered": True,
        "reason": decision.reason,
        "score": round(decision.smoothed_score, 3),
        "threshold": threshold,
        "incident_id": incident.id,
        "contacts_total": len(contacts),
        # None while the fan-out is still running. Distinct from 0, which
        # would claim we tried everyone and reached nobody.
        "contacts_notified": notified,
        "dispatch_status": incident.dispatch_status,
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
    background_tasks: BackgroundTasks,
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
        background_tasks=background_tasks,
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
    email_configured = bool(settings.email_configured) or bool(
        settings.onesignal_app_id and settings.onesignal_api_key
    )

    push = fcm_credentials(settings)

    return {
        "sms": sms_configured,
        "email": email_configured,
        "push": push.is_configured,
        # Why push is off, when it is off. A bare `false` has at least four
        # distinct causes and sends whoever is deploying to guess between
        # them -- which cost a real afternoon on the first deploy. Contains
        # no part of the credential itself.
        "push_status": push.status,
        # True when email is the only channel that can reach an ordinary
        # contact, so a contact without an address cannot be reached at all.
        "email_requires_address": email_configured and not sms_configured,
    }


@router.post("/emergency", status_code=status.HTTP_201_CREATED, response_model=IncidentPublic)
async def trigger_emergency_alert(
    payload: EmergencyAlertRequest,
    background_tasks: BackgroundTasks,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    settings: Settings = Depends(get_settings),
):
    """Records the emergency and answers immediately.

    **The fan-out to emergency contacts does not happen inside this request.**
    It used to, and that was the defect: every contact is tried on up to three
    channels with three attempts each, and a channel whose port is blocked
    fails by *timing out* rather than refusing. Two contacts against a blocked
    SMTP port took around two minutes of wall clock while the app gave up at
    fifteen seconds -- so a woman with full signal was told her alert had been
    saved for "when you have signal", and the alert she was waiting on was
    filed in an offline queue instead of being reported as sent.

    FR-EMG-01 asks for dispatch within three seconds. What must happen inside
    those three seconds is that the emergency becomes *durable* and the user
    gets an answer; who has been reached is knowable a few seconds later, and
    the client polls `GET /alerts/emergency/{id}/dispatch` for it.

    The client may supply `incident_id`. When it does, a repeat of the same
    id returns the existing incident untouched -- a phone that timed out
    waiting and retried must not file a second emergency, and must not make
    every contact's phone ring twice.
    """
    # --- idempotency -----------------------------------------------------
    # A client that never heard back does not know whether we received it. It
    # retries, and it must be safe to.
    requested_id = payload.incident_id
    if requested_id:
        existing = await session.get(Incident, requested_id)
        if existing is not None and existing.user_id == current_user.id:
            return await _incident_response(session, existing)
        if existing is not None:
            # The id belongs to someone else. **Do not refuse the SOS.** A 404
            # here would mean a client-side id collision -- or a client
            # replaying a stale id after switching accounts -- silently costs
            # someone their emergency, and no error this endpoint can return
            # is worth that. Mint a fresh id and carry on; the caller loses
            # only its idempotency guarantee, which it can survive.
            logger.warning(
                "Emergency incident id %s already belongs to another user; "
                "issuing a new id for %s",
                requested_id,
                current_user.id,
            )
            requested_id = None

    incident_id = requested_id or str(uuid4())

    # Counted before the response so the client can show the right number of
    # pending contacts straight away rather than an empty list that fills in.
    contacts = await contacts_repo.list_by_user(session, user_id=current_user.id)

    incident = Incident(
        id=incident_id,
        user_id=current_user.id,
        title="Emergency SOS",
        description=payload.summary,
        threat_level=payload.severity,
        evidence_url=None,
        dispatch_status=DISPATCH_IN_PROGRESS,
        contacts_total=len(contacts),
        contacts_notified=0,
        contacts_reached=json.dumps([]),
        contacts_failed=json.dumps([]),
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

    # FR-EMG-04/05: notify the people who can actually help. Queued rather
    # than awaited -- see the docstring. The incident is committed above, so
    # the task has a durable row to record its outcome against even if this
    # process dies before it runs.
    background_tasks.add_task(
        run_dispatch_in_background,
        settings=settings,
        user_id=current_user.id,
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
    response.dispatch_status = DISPATCH_IN_PROGRESS
    response.contacts_total = len(contacts)
    # Explicitly zero and empty, not null: the fan-out has started and has
    # reached nobody *yet*. Null would mean no dispatch was attempted, which
    # is the one thing this is not.
    response.contacts_notified = 0
    response.contacts_reached = []
    response.contacts_failed = []
    return response


@router.get("/emergency/{incident_id}/dispatch")
async def get_dispatch_status(
    incident_id: str,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    """How the contact fan-out for one incident is going.

    Polled by the Emergency screen while it shows "Help is on the way". The
    screen marks exactly the contacts named in `contacts_reached` and shows
    the ones in `contacts_failed` as unreachable -- an aggregate count alone
    would make it guess which, and guessing wrong here tells someone in danger
    that her sister knows when nothing arrived.
    """
    incident = await session.get(Incident, incident_id)
    if incident is None or incident.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found")

    return {
        "incident_id": incident.id,
        # NULL status means this incident was filed by some route that never
        # dispatched. Reported as-is rather than coerced to "complete".
        "status": incident.dispatch_status,
        "contacts_total": incident.contacts_total,
        "contacts_notified": incident.contacts_notified,
        "contacts_reached": _json_ids(incident.contacts_reached),
        "contacts_failed": _json_ids(incident.contacts_failed),
        "completed_at": (
            incident.dispatch_completed_at.isoformat()
            if incident.dispatch_completed_at
            else None
        ),
    }


def _json_ids(raw: Optional[str]) -> list[str]:
    """Reads a stored id list, tolerating anything that is not one.

    A malformed column must not turn a status poll into a 500 -- the client
    asking is on the Emergency screen.
    """
    if not raw:
        return []
    try:
        parsed = json.loads(raw)
    except (ValueError, TypeError):
        return []
    return [str(item) for item in parsed] if isinstance(parsed, list) else []


async def _incident_response(session: AsyncSession, incident: Incident) -> IncidentPublic:
    """Builds the response for an incident that already existed.

    Used by the idempotent replay path, which must answer with what the first
    request produced rather than a fresh, emptier version of it.
    """
    response = IncidentPublic.model_validate(incident)
    location = (
        await session.execute(
            select(Location).where(Location.incident_id == incident.id).limit(1)
        )
    ).scalars().first()
    if location is not None:
        response.latitude = location.lat
        response.longitude = location.lng
        response.location_accuracy = location.accuracy
    # The dispatch fields need no assignment here: they are real columns on
    # `Incident`, and `IncidentPublic` decodes the stored JSON text itself
    # (see its `_decode_id_list` validator). Only the location has to be
    # attached by hand, because one incident can have several location rows
    # and so it is not a mapped attribute.
    return response


@router.post("/heartbeat", status_code=status.HTTP_202_ACCEPTED)
async def submit_heartbeat(
    payload: HeartbeatRequest,
    background_tasks: BackgroundTasks,
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
        background_tasks=background_tasks,
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

@router.get("/models")
async def get_model_registry(
    current_user: UserPublic = Depends(get_current_user),
):
    """What the threat pipeline is currently capable of.

    Exists so "why did nothing trigger?" has an answer that does not require
    reading the source. While no model is trained this reports
    `scores_are_caller_supplied: true`, which is the honest description of
    every score the backend currently receives.
    """
    return threat_models.registry_report()


@router.post("/analyze", status_code=status.HTTP_202_ACCEPTED)
async def analyze_model_scores(
    payload: ModelScoresRequest,
    background_tasks: BackgroundTasks,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    settings: Settings = Depends(get_settings),
):
    """Run SRS §6.2 over one synchronised read from the wearables.

    This is the entry point the three models feed once they are trained:
    XGBoost over the glove's IMU, CNN+LSTM over the glasses' microphone and
    YOLOv8 over its camera. It takes scores rather than frames so a model
    can move between firmware, phone and server without this contract
    changing (SRS §6.3 splits them across exactly that boundary).

    A read with no modality at all is rejected. Scoring it would mean
    inventing a number for a moment nothing observed, and that number would
    then be smoothed into every reading after it.
    """
    scores = threat_models.ModalityScores(
        motion=payload.motion_score,
        audio=payload.audio_score,
        vision=payload.vision_score,
        weapon_confidence=payload.weapon_confidence,
        heart_rate_bpm=payload.heart_rate_bpm,
    )
    if not scores.has_any:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                "No modality reported. Send at least one of motion_score, "
                "audio_score or vision_score."
            ),
        )

    # The wire names predate the three-signal architecture and are kept so
    # the API does not break: motion is the glove's XGBoost output, vision is
    # YOLOv8 weapon detection, audio is the CNN+LSTM threat/help classifier.
    fused = threat_fusion.fuse(
        threat_fusion.ThreatSignals(
            glove=scores.motion, weapon=scores.vision, audio=scores.audio
        )
    )
    # Heart rate is deliberately no longer added. A racing pulse is evidence of
    # running for a bus; it is carried as supporting context on the incident.

    if payload.location:
        session.add(
            Location(
                user_id=current_user.id,
                device_id=payload.device_id,
                lat=float(payload.location.get("latitude", 0.0)),
                lng=float(payload.location.get("longitude", 0.0)),
                accuracy=payload.location.get("accuracy"),
            )
        )
        await session.commit()

    auto_sos = await _auto_dispatch_if_threatened(
        background_tasks=background_tasks,
        session=session,
        settings=settings,
        user_id=current_user.id,
        raw_score=fused,
        weapon_confidence=scores.weapon_confidence,
        in_high_risk_zone=payload.in_high_risk_zone,
        scores=scores,
        weapon_label=payload.weapon_label,
    )

    _latest_scores[current_user.id] = {
        "score": round(fused * 100, 2),
        "level": _to_level(fused * 100),
        "updated_at": (payload.timestamp or datetime.utcnow()).isoformat(),
    }

    return {
        "fused_score": round(fused, 4),
        # The same sentence written onto the incident, returned so a caller
        # can show it without a second request.
        "findings": threat_models.describe(scores, weapon_label=payload.weapon_label),
        # Which sensors this verdict actually rests on. A score fused from
        # the glove alone means something different from one that also saw
        # and heard, and a reader cannot tell them apart from the number.
        "modalities_used": scores.reporting_modalities,
        "live_score": _latest_scores[current_user.id],
        "auto_sos": auto_sos,
    }


@router.post("/weapon-frame")
async def analyse_weapon_frame(
    file: UploadFile = File(...),
    current_user: UserPublic = Depends(get_current_user),
    settings: Settings = Depends(get_settings),
):
    """Scores one camera frame — the web fallback for weapon detection.

    **Android does not use this.** There the detector runs on the phone against
    a continuous stream from the glasses and no video leaves the device. Web has
    no on-device runtime, so it posts occasional frames here instead, and the
    two are not the same promise: one is continuous and local, the other is
    sampled and uploaded. The client is required to say which it is running.

    Nothing is stored. The frame is decoded, scored and dropped — it is not
    evidence, nobody chose to record it, and keeping it would turn a detection
    check into surveillance of every journey.

    Returns `available: false` when no model is loaded, so the caller reports
    the modality as **absent** rather than as a zero score. A zero would claim
    the camera looked and saw calm, which caps the fused score below the alarm
    threshold and quietly disables automatic dispatch.
    """
    content_type = (file.content_type or "").split(";")[0].strip().lower()
    if content_type not in {"image/jpeg", "image/jpg", "image/png"}:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Frame must be a JPEG or PNG image.",
        )

    # Read with a cap rather than trusting Content-Length, which the client
    # controls. One byte over is enough to reject.
    limit = settings.weapon_frame_max_size_bytes
    data = await file.read(limit + 1)
    if len(data) > limit:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Frame is too large.",
        )
    if not data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Frame is empty."
        )

    if weapon_detector.weapon_status() is not threat_models.ModelStatus.READY:
        return {
            "available": False,
            "reason": weapon_detector.weapon_status().value,
            "weapon_confidence": None,
            "weapon_label": None,
        }

    try:
        verdict = await run_in_threadpool(weapon_detector.analyse_frame, data)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Frame could not be decoded.",
        )

    return {
        "available": True,
        "weapon_confidence": round(verdict.weapon_confidence, 4),
        "weapon_label": verdict.weapon_label,
        # Supporting context. Deliberately NOT a fusion input — see
        # `threat_fusion` for why expression cannot move the threat score, and
        # `tests/test_fusion_architecture.py` for the test that keeps it out.
        "supporting_context": {
            "emotion_label": verdict.emotion_label,
            "emotion_confidence": (
                round(verdict.emotion_confidence, 4)
                if verdict.emotion_confidence is not None
                else None
            ),
        },
    }
