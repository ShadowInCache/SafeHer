from fastapi_app.models import NotificationLog
from sqlalchemy.ext.asyncio import AsyncSession


async def create_log(
    session: AsyncSession,
    *,
    user_id: str | None,
    device_id: str | None,
    token: str | None,
    channel: str,
    status: str,
    payload: str | None,
) -> NotificationLog:
    log = NotificationLog(
        user_id=user_id,
        device_id=device_id,
        token=token,
        channel=channel,
        status=status,
        payload=payload,
    )
    session.add(log)
    await session.commit()
    await session.refresh(log)
    return log
