import secrets
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.models import Device


async def create(session: AsyncSession, *, user_id: str, device_name: str, device_type: str) -> Device:
    auth_secret = secrets.token_hex(16)
    device = Device(
        user_id=user_id,
        device_name=device_name,
        device_type=device_type,
        auth_secret=auth_secret,
    )
    session.add(device)
    await session.commit()
    await session.refresh(device)
    return device


async def get_by_id(session: AsyncSession, device_id: str) -> Optional[Device]:
    return await session.get(Device, device_id)


async def list_by_user(session: AsyncSession, user_id: str) -> list[Device]:
    result = await session.execute(select(Device).where(Device.user_id == user_id))
    return result.scalars().all()


async def delete(session: AsyncSession, *, device: Device) -> None:
    """Removes a device and everything hanging off it.

    Push tokens are the reason this is not a bare row delete: a token left
    behind would keep an unpaired wearable's handset receiving this account's
    emergency notifications.
    """
    await session.delete(device)
    await session.commit()
