import json

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from fastapi_app.config import get_settings
from fastapi_app.db import SessionLocal
from fastapi_app.realtime import manager
from fastapi_app.repositories import users as user_repo
from fastapi_app.security import decode_token

router = APIRouter(prefix="/api/v1/ws", tags=["ws"])


@router.websocket("/alerts/{user_id}")
async def websocket_alerts(websocket: WebSocket, user_id: str, token: str):
    settings = get_settings()
    try:
        payload = decode_token(token, settings, expected_type="access")
    except Exception:
        await websocket.close(code=1008)
        return

    async with SessionLocal() as session:
        user = await user_repo.get_by_email(session, payload.sub)
    if not user or not user.is_active or user.id != user_id:
        await websocket.close(code=1008)
        return

    await manager.connect(websocket, user_id=user_id)
    try:
        while True:
            msg = await websocket.receive_text()
            try:
                payload_msg = json.loads(msg)
            except json.JSONDecodeError:
                payload_msg = None

            if isinstance(payload_msg, dict) and payload_msg.get("type") == "ping":
                await websocket.send_json({"type": "pong"})
                continue

            if msg.lower() == "ping":
                await websocket.send_text("pong")
    except WebSocketDisconnect:
        manager.disconnect(websocket, user_id=user_id)
    except Exception:
        manager.disconnect(websocket, user_id=user_id)
        await websocket.close(code=1011)
