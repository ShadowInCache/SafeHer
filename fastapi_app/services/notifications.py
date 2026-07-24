from typing import Any, Dict, Optional

import httpx
from fastapi import HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.models import NotificationLog

FCM_URL = "https://fcm.googleapis.com/fcm/send"


def _require_fcm_key(server_key: Optional[str]) -> str:
    if not server_key:
        raise HTTPException(status_code=500, detail="FCM not configured")
    return server_key


async def send_fcm_notification(
    *,
    server_key: Optional[str],
    token: str,
    title: str,
    body: str,
    data: Optional[Dict[str, Any]] = None,
    session: Optional[AsyncSession] = None,
    user_id: Optional[str] = None,
    device_id: Optional[str] = None,
) -> Dict[str, Any]:
    key = _require_fcm_key(server_key)

    payload = {
        "to": token,
        "notification": {"title": title, "body": body},
        "data": data or {},
    }
    headers = {
        "Authorization": f"key={key}",
        "Content-Type": "application/json",
    }

    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.post(FCM_URL, json=payload, headers=headers)

    status = "sent" if resp.status_code < 300 else "failed"

    if session is not None:
        log = NotificationLog(
            user_id=user_id,
            device_id=device_id,
            token=token,
            channel="fcm",
            status=status,
            payload=str(payload),
        )
        session.add(log)
        await session.commit()

    if resp.status_code >= 300:
        raise HTTPException(status_code=resp.status_code, detail=f"FCM send failed: {resp.text}")

    return resp.json()
