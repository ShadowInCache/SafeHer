from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.models import FcmToken


async def register_token(session: AsyncSession, *, user_id: str, device_id: Optional[str], token: str) -> FcmToken:
    # Upsert behavior: if token exists, update links
    existing = await session.execute(select(FcmToken).where(FcmToken.token == token))
    existing_token = existing.scalar_one_or_none()
    if existing_token:
        existing_token.user_id = user_id
        existing_token.device_id = device_id
        await session.commit()
        await session.refresh(existing_token)
        return existing_token

    fcm = FcmToken(user_id=user_id, device_id=device_id, token=token)
    session.add(fcm)
    await session.commit()
    await session.refresh(fcm)
    return fcm


async def list_by_user(session: AsyncSession, *, user_id: str) -> list[FcmToken]:
    rows = await session.execute(select(FcmToken).where(FcmToken.user_id == user_id))
    return rows.scalars().all()
