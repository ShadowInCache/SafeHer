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
    contact = await emergency_repo.get_by_id(session, contact_id=contact_id)
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
    contact = await emergency_repo.get_by_id(session, contact_id=contact_id)
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
    contact = await emergency_repo.get_by_id(session, contact_id=contact_id)
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
    contact = await emergency_repo.get_by_id(session, contact_id=contact_id)
    if not contact or contact.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Contact not found")

    await emergency_repo.delete_by_id(session, contact_id=contact_id)
    return None
