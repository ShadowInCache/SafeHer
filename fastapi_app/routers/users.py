from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.config import Settings, get_settings
from fastapi_app.db import get_session
from fastapi_app.repositories import emergency_contacts as emergency_repo
from fastapi_app.repositories import users as user_repo
from fastapi_app.schemas import (
    ContactVerifyRequest,
    EmergencyContactCreate,
    EmergencyContactPublic,
    EmergencyContactUpdate,
    UserPublic,
    UserUpdate,
)
from fastapi_app.security import get_current_user
from fastapi_app.services.contact_verification import (
    ContactVerificationError,
    confirm_verification_code,
    invalidate_verification,
    send_verification_code,
)

# SRS FR-EMG-10: "Emergency contacts: up to 10".
MAX_EMERGENCY_CONTACTS = 10

router = APIRouter(prefix="/api/v1/users", tags=["users"])


@router.get("/me", response_model=UserPublic)
async def get_me(current_user: UserPublic = Depends(get_current_user)):
    return current_user


@router.get("/me/export")
async def export_my_data(
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    """Everything SafeHer holds about this account, as one JSON document.

    GDPR Article 15 (right of access), the counterpart to the Article 17
    erasure already implemented as `DELETE /auth/account`. The app offered a
    "Download My Data" button for both, and only deletion existed — the export
    sheet said so in small print, which is an honest placeholder and not a
    feature.

    **What is deliberately not here.** Evidence recordings are referenced by
    id and metadata, never inlined. They are stored encrypted and streamed
    per request by `/media/evidence/{id}`, and base64-ing an assault recording
    into a JSON blob that then lands in a Downloads folder would undo the
    reason it is encrypted at rest in the first place. The same reasoning
    keeps password hashes, OTP hashes, safety-PIN hashes and share tokens out:
    an export is a document the user will store somewhere less careful than a
    database, so it carries her data and not her credentials.
    """
    from sqlalchemy import select

    from fastapi_app.models import (
        Device,
        EmergencyContact,
        Incident,
        Location,
        Media,
        NotificationLog,
        SafeJourney,
        User,
    )

    async def rows(model, *, order=None):
        statement = select(model).where(model.user_id == current_user.id)
        if order is not None:
            statement = statement.order_by(order)
        return (await session.execute(statement)).scalars().all()

    def when(value):
        return value.isoformat() if value else None

    user = await session.get(User, current_user.id)

    incidents = await rows(Incident, order=Incident.created_at)
    contacts = await rows(EmergencyContact, order=EmergencyContact.priority)
    devices = await rows(Device)
    locations = await rows(Location, order=Location.captured_at)
    journeys = await rows(SafeJourney)
    notifications = await rows(NotificationLog)

    # Media hangs off the incident, not the user -- there is no `user_id` on
    # the row. Scoped through this user's own incident ids so the export
    # cannot reach anyone else's recordings.
    incident_ids = [incident.id for incident in incidents]
    media = (
        (
            await session.execute(
                select(Media).where(Media.incident_id.in_(incident_ids))
            )
        )
        .scalars()
        .all()
        if incident_ids
        else []
    )

    return {
        "export_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "account": {
            "id": user.id,
            "email": user.email,
            "full_name": user.full_name,
            "phone": user.phone,
            "role": user.role,
            "is_active": user.is_active,
            "is_verified": user.is_verified,
            "created_at": when(user.created_at),
            "deletion_requested_at": when(user.deletion_requested_at),
            "notification_preferences": {
                "push": user.push_notifications,
                "sms": user.sms_notifications,
                "email": user.email_notifications,
                "location_sharing": user.location_sharing,
            },
            "threat_threshold": user.threat_threshold,
        },
        "emergency_contacts": [
            {
                "id": contact.id,
                "name": contact.name,
                "phone": contact.phone,
                "email": contact.email,
                "relationship": contact.relationship,
                "priority": contact.priority,
                "verified_at": when(contact.verified_at),
                "created_at": when(contact.created_at),
            }
            for contact in contacts
        ],
        "devices": [
            {
                "id": device.id,
                "name": device.device_name,
                "type": device.device_type,
                "is_active": device.is_active,
                "battery_level": device.battery_level,
                "firmware_version": device.firmware_version,
                "last_seen": when(device.last_seen),
                "created_at": when(device.created_at),
            }
            for device in devices
        ],
        "incidents": [
            {
                "id": incident.id,
                "title": incident.title,
                "description": incident.description,
                "threat_level": incident.threat_level,
                "auto_dispatched": incident.auto_dispatched,
                "detections": incident.detections,
                "motion_score": incident.motion_score,
                "audio_score": incident.audio_score,
                "vision_score": incident.vision_score,
                "weapon_confidence": incident.weapon_confidence,
                "fused_score": incident.fused_score,
                "threshold_used": incident.threshold_used,
                "ai_summary": incident.ai_summary,
                "dispatch_status": incident.dispatch_status,
                "contacts_total": incident.contacts_total,
                "contacts_notified": incident.contacts_notified,
                "created_at": when(incident.created_at),
            }
            for incident in incidents
        ],
        "locations": [
            {
                "id": location.id,
                "incident_id": location.incident_id,
                "journey_id": location.journey_id,
                "latitude": location.lat,
                "longitude": location.lng,
                "accuracy": location.accuracy,
                "captured_at": when(location.captured_at),
            }
            for location in locations
        ],
        "safe_journeys": [
            {
                "id": journey.id,
                "destination": getattr(journey, "destination_label", None),
                "status": journey.status,
                "expected_arrival": when(journey.expected_arrival_at),
                "started_at": when(journey.started_at),
                "ended_at": when(journey.ended_at),
                "created_at": when(journey.created_at),
            }
            for journey in journeys
        ],
        # Referenced, not inlined -- see the docstring.
        "evidence": [
            {
                "id": item.id,
                "incident_id": item.incident_id,
                "media_type": item.media_type,
                "size_bytes": item.size_bytes,
                "created_at": when(item.created_at),
                "download": f"/api/v1/media/evidence/{item.id}",
            }
            for item in media
        ],
        "notification_log": [
            {
                "channel": entry.channel,
                "status": entry.status,
                "payload": entry.payload,
                "created_at": when(entry.created_at),
            }
            for entry in notifications
        ],
    }


@router.patch("/me", response_model=UserPublic)
async def update_me(
    payload: UserUpdate,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    user = await user_repo.get_by_id(session, current_user.id)
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    updated = await user_repo.update(
        session,
        user=user,
        full_name=payload.full_name,
        phone=payload.phone,
        avatar_url=payload.avatar_url,
        push_notifications=payload.push_notifications,
        sms_notifications=payload.sms_notifications,
        email_notifications=payload.email_notifications,
        location_sharing=payload.location_sharing,
        threat_threshold=payload.threat_threshold,
    )
    return UserPublic.model_validate(updated)


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_me(
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    user = await user_repo.get_by_id(session, current_user.id)
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    await user_repo.delete_cascade(session, user=user)
    return None


@router.get("/me/emergency-contacts", response_model=list[EmergencyContactPublic])
async def list_emergency_contacts(
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    return await emergency_repo.list_by_user(session, user_id=current_user.id)


@router.post(
    "/me/emergency-contacts",
    response_model=EmergencyContactPublic,
    status_code=status.HTTP_201_CREATED,
)
async def create_emergency_contact(
    payload: EmergencyContactCreate,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    # SRS FR-EMG-10 caps the list at ten. The cap is not arbitrary: every
    # contact is messaged on every alert, and a list long enough to be
    # unmaintained is a list full of stale addresses.
    existing = await emergency_repo.list_by_user(session, user_id=current_user.id)
    if len(existing) >= MAX_EMERGENCY_CONTACTS:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"You can have at most {MAX_EMERGENCY_CONTACTS} emergency contacts.",
        )

    return await emergency_repo.create(
        session,
        contact_id=payload.id,
        user_id=current_user.id,
        name=payload.name,
        phone=payload.phone,
        email=payload.email,
        relationship=payload.relationship,
        priority=payload.priority,
    )


@router.put("/me/emergency-contacts/{contact_id}", response_model=EmergencyContactPublic)
async def update_emergency_contact(
    contact_id: str,
    payload: EmergencyContactUpdate,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    contact = await emergency_repo.get_by_id(session, contact_id=contact_id, user_id=current_user.id)
    if not contact or contact.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Contact not found")

    # An address change drops verification: a tick earned at one address
    # says nothing about a different one, and leaving it would hide exactly
    # the typo this feature exists to catch.
    if payload.email is not None and payload.email != contact.email:
        invalidate_verification(contact)

    return await emergency_repo.update(
        session,
        contact=contact,
        name=payload.name,
        phone=payload.phone,
        email=payload.email,
        relationship=payload.relationship,
        priority=payload.priority,
    )


@router.post("/me/emergency-contacts/{contact_id}/verify/send", status_code=status.HTTP_202_ACCEPTED)
async def send_contact_verification(
    contact_id: str,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    settings: Settings = Depends(get_settings),
):
    """Emails this contact a code to pass back to the user."""
    contact = await emergency_repo.get_by_id(session, contact_id=contact_id, user_id=current_user.id)
    if not contact or contact.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Contact not found")

    if contact.verified_at is not None:
        return {"already_verified": True}

    try:
        await send_verification_code(
            session,
            settings=settings,
            contact=contact,
            user_name=current_user.full_name or current_user.email,
        )
    except ContactVerificationError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    except Exception as exc:  # delivery failed
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Could not send the code: {exc}",
        )

    return {"already_verified": False}


@router.post("/me/emergency-contacts/{contact_id}/verify", response_model=EmergencyContactPublic)
async def confirm_contact_verification(
    contact_id: str,
    payload: ContactVerifyRequest,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    contact = await emergency_repo.get_by_id(session, contact_id=contact_id, user_id=current_user.id)
    if not contact or contact.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Contact not found")

    try:
        verified = await confirm_verification_code(session, contact=contact, code=payload.code)
    except ContactVerificationError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))

    if not verified:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="That code is not correct."
        )

    return contact


@router.delete("/me/emergency-contacts/{contact_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_emergency_contact(
    contact_id: str,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    contact = await emergency_repo.get_by_id(session, contact_id=contact_id, user_id=current_user.id)
    if not contact or contact.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Contact not found")

    await emergency_repo.delete_by_id(session, contact_id=contact_id, user_id=current_user.id)
    return None
