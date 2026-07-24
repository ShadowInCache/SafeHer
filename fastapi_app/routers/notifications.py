from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.db import get_session
from fastapi_app.repositories import fcm_tokens
from fastapi_app.schemas import UserPublic
from fastapi_app.security import get_current_user
from pydantic import BaseModel

router = APIRouter(prefix="/api/v1/notifications", tags=["notifications"])


class RegisterTokenRequest(BaseModel):
    token: str
    device_id: str | None = None


@router.post("/register-token", status_code=status.HTTP_204_NO_CONTENT)
async def register_token(
    payload: RegisterTokenRequest,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    if not payload.token:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="token is required")
    await fcm_tokens.register_token(session, user_id=current_user.id, device_id=payload.device_id, token=payload.token)
    return None


@router.get("/tokens")
async def list_tokens(
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    tokens = await fcm_tokens.list_by_user(session, user_id=current_user.id)
    return {
        "tokens": [
            {
                "id": item.id,
                "device_id": item.device_id,
                "token": item.token,
                "created_at": item.created_at,
            }
            for item in tokens
        ]
    }
