from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.models import User


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
) -> User:
    user = User(email=email.lower(), password_hash=password_hash, full_name=full_name, role=role)
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return user


async def exists(session: AsyncSession, email: str) -> bool:
    return bool(await get_by_email(session, email))
