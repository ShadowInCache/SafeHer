from typing import Optional

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.models import EmergencyContact


async def list_by_user(session: AsyncSession, *, user_id: str) -> list[EmergencyContact]:
    rows = await session.execute(
        select(EmergencyContact)
        .where(EmergencyContact.user_id == user_id)
        .order_by(EmergencyContact.priority.asc(), EmergencyContact.created_at.desc())
    )
    return rows.scalars().all()


async def get_by_id(session: AsyncSession, *, contact_id: str) -> Optional[EmergencyContact]:
    return await session.get(EmergencyContact, contact_id)


async def create(
    session: AsyncSession,
    *,
    contact_id: Optional[str],
    user_id: str,
    name: str,
    phone: str,
    email: Optional[str],
    relationship: Optional[str],
    priority: int,
) -> EmergencyContact:
    item = EmergencyContact(
        id=contact_id,
        user_id=user_id,
        name=name,
        phone=phone,
        email=email,
        relationship=relationship,
        priority=priority,
    )
    session.add(item)
    await session.commit()
    await session.refresh(item)
    return item


async def update(
    session: AsyncSession,
    *,
    contact: EmergencyContact,
    name: Optional[str] = None,
    phone: Optional[str] = None,
    email: Optional[str] = None,
    relationship: Optional[str] = None,
    priority: Optional[int] = None,
) -> EmergencyContact:
    if name is not None:
        contact.name = name
    if phone is not None:
        contact.phone = phone
    if email is not None:
        contact.email = email
    if relationship is not None:
        contact.relationship = relationship
    if priority is not None:
        contact.priority = priority

    await session.commit()
    await session.refresh(contact)
    return contact


async def delete_by_id(session: AsyncSession, *, contact_id: str) -> bool:
    result = await session.execute(delete(EmergencyContact).where(EmergencyContact.id == contact_id))
    await session.commit()
    return bool(result.rowcount)
