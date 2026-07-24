from datetime import datetime
from typing import Optional

import cloudinary
from cloudinary.utils import api_sign_request
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from fastapi_app.config import Settings, get_settings
from fastapi_app.schemas import UserPublic
from fastapi_app.security import get_current_user

router = APIRouter(prefix="/api/v1/media", tags=["media"])


class SignUploadRequest(BaseModel):
    folder: str = Field(default="evidence", description="Cloudinary folder to store uploads")
    public_id: Optional[str] = Field(default=None, description="Optional public_id to control filename")
    resource_type: str = Field(default="auto", description="Cloudinary resource type (image, video, raw, auto)")


@router.post("/sign-upload")
async def sign_upload(
    payload: SignUploadRequest,
    settings: Settings = Depends(get_settings),
    current_user: UserPublic = Depends(get_current_user),
):
    if not (settings.cloudinary_cloud_name and settings.cloudinary_api_key and settings.cloudinary_api_secret):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cloudinary is not configured")

    allowed_resource_types = {"image", "video", "raw", "auto"}
    if payload.resource_type not in allowed_resource_types:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid resource_type")

    if ".." in payload.folder:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid folder name")

    cloudinary.config(
        cloud_name=settings.cloudinary_cloud_name,
        api_key=settings.cloudinary_api_key,
        api_secret=settings.cloudinary_api_secret,
        secure=True,
    )

    timestamp = int(datetime.utcnow().timestamp())
    params = {
        "timestamp": timestamp,
        "folder": payload.folder,
    }
    if payload.public_id:
        params["public_id"] = payload.public_id

    signature = api_sign_request(params, settings.cloudinary_api_secret)
    upload_url = f"https://api.cloudinary.com/v1_1/{settings.cloudinary_cloud_name}/{payload.resource_type}/upload"

    return {
        "cloud_name": settings.cloudinary_cloud_name,
        "api_key": settings.cloudinary_api_key,
        "signature": signature,
        "timestamp": timestamp,
        "folder": payload.folder,
        "public_id": payload.public_id,
        "upload_url": upload_url,
        "resource_type": payload.resource_type,
    }
