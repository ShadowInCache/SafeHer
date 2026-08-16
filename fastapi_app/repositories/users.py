from typing import Optional

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.models import Device, EmergencyContact, FcmToken, Incident, Location, Media, NotificationLog, User


async def get_by_email(session: AsyncSession, email: str) -> Optional[User]:
    result = await session.execute(select(User).where(User.email == email.lower()))
    return result.scalar_one_or_none()


async def create(
    session: AsyncSession,
    *,
    email: str,
    password_hash: str,
    full_name: Optional[str],
    role: str = "user",
    phone: Optional[str] = None,
) -> User:
    user = User(email=email.lower(), password_hash=password_hash, full_name=full_name, role=role, phone=phone)
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return user


async def exists(session: AsyncSession, email: str) -> bool:
    return bool(await get_by_email(session, email))


async def get_by_id(session: AsyncSession, user_id: str) -> Optional[User]:
    result = await session.execute(select(User).where(User.id == user_id))
    return result.scalar_one_or_none()


async def update(
    session: AsyncSession,
    *,
    user: User,
    full_name: Optional[str] = None,
    phone: Optional[str] = None,
    avatar_url: Optional[str] = None,
    push_notifications: Optional[bool] = None,
    sms_notifications: Optional[bool] = None,
    email_notifications: Optional[bool] = None,
    location_sharing: Optional[bool] = None,
    threat_threshold: Optional[float] = None,
) -> User:
    if threat_threshold is not None:
        user.threat_threshold = threat_threshold
    if full_name is not None:
        user.full_name = full_name
    if phone is not None:
        user.phone = phone
    if avatar_url is not None:
        user.avatar_url = avatar_url
    if push_notifications is not None:
        user.push_notifications = push_notifications
    if sms_notifications is not None:
        user.sms_notifications = sms_notifications
    if email_notifications is not None:
        user.email_notifications = email_notifications
    if location_sharing is not None:
        user.location_sharing = location_sharing
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return user


async def delete_cascade(session: AsyncSession, *, user: User) -> None:
    """Deletes a user and every row that references them.

    FK `ondelete="CASCADE"` is declared on the dependent tables, but SQLite
    doesn't enforce foreign keys unless `PRAGMA foreign_keys=ON` is set on
    the connection (it isn't here), so relying on DB-level cascade would
    silently leave orphaned rows on SQLite while working on Postgres —
    deleting explicitly is correct on both.
    """
    incident_ids = (await session.execute(select(Incident.id).where(Incident.user_id == user.id))).scalars().all()
    if incident_ids:
        await session.execute(delete(Media).where(Media.incident_id.in_(incident_ids)))
    await session.execute(delete(Location).where(Location.user_id == user.id))
    await session.execute(delete(FcmToken).where(FcmToken.user_id == user.id))
    await session.execute(delete(NotificationLog).where(NotificationLog.user_id == user.id))
    await session.execute(delete(EmergencyContact).where(EmergencyContact.user_id == user.id))
    await session.execute(delete(Device).where(Device.user_id == user.id))
    await session.execute(delete(Incident).where(Incident.user_id == user.id))
    await session.delete(user)
    await session.commit()
