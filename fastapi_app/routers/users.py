from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.db import get_session
from fastapi_app.repositories import emergency_contacts as emergency_repo
from fastapi_app.schemas import (
    EmergencyContactCreate,
    EmergencyContactPublic,
    EmergencyContactUpdate,
    UserPublic,
)
from fastapi_app.security import get_current_user

router = APIRouter(prefix="/api/v1/users", tags=["users"])


@router.get("/me", response_model=UserPublic)
async def get_me(current_user: UserPublic = Depends(get_current_user)):
    return current_user


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

    return await emergency_repo.update(
        session,
        contact=contact,
        name=payload.name,
        phone=payload.phone,
        email=payload.email,
        relationship=payload.relationship,
        priority=payload.priority,
    )


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
