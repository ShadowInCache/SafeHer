from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.db import get_session
from fastapi_app.repositories import devices as device_repo
from fastapi_app.schemas import DeviceHeartbeatRequest, DevicePublic, DeviceRegisterRequest, UserPublic
from fastapi_app.security import get_current_user

router = APIRouter(prefix="/api/v1/devices", tags=["devices"])


@router.post("/register", response_model=DevicePublic)
async def register_device(
    payload: DeviceRegisterRequest,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    device = await device_repo.create(
        session,
        user_id=current_user.id,
        device_name=payload.device_name,
        device_type=payload.device_type,
    )
    return device


@router.get("/me", response_model=list[DevicePublic])
async def list_my_devices(
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    devices = await device_repo.list_by_user(session, current_user.id)
    return devices


@router.post("/{device_id}/heartbeat", status_code=status.HTTP_204_NO_CONTENT)
async def update_device_heartbeat(
    device_id: str,
    payload: DeviceHeartbeatRequest,
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    device = await device_repo.get_by_id(session, device_id)
    if not device or device.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found")

    device.last_seen = datetime.utcnow()
    await session.commit()
    return None
