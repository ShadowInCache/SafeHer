"""The live alert feed, and the ticket that opens it.

**Why there is a ticket at all.** A WebSocket handshake carries no
`Authorization` header when it is opened from a browser -- the JavaScript API
has nowhere to put one -- so the credential has to go in the URL. That is the
worst place for one: query strings are written into proxy and access logs,
kept in browser history, and handed on in referrers. Putting a 15-minute
access token there means every hop between the phone and the app holds a
working credential in plain text.

So the client asks for a ticket over ordinary authenticated HTTP, where the
token stays in a header, and spends the ticket on the handshake. The ticket
lives thirty seconds, opens nothing but this feed, and is refused anywhere an
access token is expected.
"""

import json
import logging

from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect

from fastapi_app.config import Settings, get_settings
from fastapi_app.db import SessionLocal
from fastapi_app.realtime import manager
from fastapi_app.repositories import users as user_repo
from fastapi_app.schemas import UserPublic
from fastapi_app.security import create_ws_ticket, decode_token, get_current_user

router = APIRouter(prefix="/api/v1/ws", tags=["ws"])

logger = logging.getLogger(__name__)


@router.post("/ticket")
async def issue_ws_ticket(
    current_user: UserPublic = Depends(get_current_user),
    settings: Settings = Depends(get_settings),
):
    """Mints a short-lived credential for `WS /api/v1/ws/alerts/{user_id}`.

    Authenticated the normal way, so the access token travels in a header and
    never reaches a URL. The reply says when the ticket dies, so a client can
    decide to fetch a fresh one rather than open a handshake it knows will be
    refused.
    """
    return {
        "ticket": create_ws_ticket(
            subject=current_user.email,
            role=current_user.role,
            settings=settings,
        ),
        "expires_in": settings.ws_ticket_expire_seconds,
        "user_id": current_user.id,
    }


@router.websocket("/alerts/{user_id}")
async def websocket_alerts(
    websocket: WebSocket,
    user_id: str,
    ticket: str | None = None,
    token: str | None = None,
):
    settings = get_settings()

    # A ticket is the supported credential. `token` is the previous handshake,
    # accepted only while an operator has explicitly opted in for clients that
    # predate the ticket endpoint -- it puts a full access token in the URL,
    # which is the whole problem this route was changed to solve.
    if ticket:
        credential, expected_type = ticket, "ws_ticket"
    elif token and settings.ws_allow_legacy_token_query:
        credential, expected_type = token, "access"
        logger.info("Legacy ?token= websocket handshake accepted; client needs updating")
    else:
        await websocket.close(code=1008)
        return

    try:
        payload = decode_token(credential, settings, expected_type=expected_type)
    except Exception:
        await websocket.close(code=1008)
        return

    async with SessionLocal() as session:
        user = await user_repo.get_by_email(session, payload.sub)
    # The id in the path is an assertion by the caller and nothing more: it has
    # to match the identity the credential actually proves.
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
