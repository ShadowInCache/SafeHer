from datetime import datetime
from typing import Any, Optional
from uuid import uuid4

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class UserBase(BaseModel):
    email: EmailStr
    role: str = "user"
    is_active: bool = True


class UserCreate(UserBase):
    password: str = Field(min_length=8)
    full_name: Optional[str] = None


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserPublic(UserBase):
    id: str = Field(default_factory=lambda: str(uuid4()))
    full_name: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


class Token(BaseModel):
    access_token: str
    refresh_token: Optional[str] = None
    token_type: str = "bearer"


class TokenPayload(BaseModel):
    sub: str
    role: str
    exp: int
    type: str = "access"


class TokenRefreshRequest(BaseModel):
    refresh_token: str


class FirebaseTokenExchangeRequest(BaseModel):
    id_token: str = Field(min_length=10)
    role: str = Field(default="user")
    full_name: Optional[str] = None


class EmergencyContactBase(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    phone: str = Field(min_length=5, max_length=32)
    email: Optional[EmailStr] = None
    relationship: Optional[str] = Field(default="trusted_contact", max_length=64)
    priority: int = Field(default=1, ge=1, le=10)


class EmergencyContactCreate(EmergencyContactBase):
    id: Optional[str] = None


class EmergencyContactUpdate(BaseModel):
    name: Optional[str] = Field(default=None, min_length=1, max_length=120)
    phone: Optional[str] = Field(default=None, min_length=5, max_length=32)
    email: Optional[EmailStr] = None
    relationship: Optional[str] = Field(default=None, max_length=64)
    priority: Optional[int] = Field(default=None, ge=1, le=10)


class EmergencyContactPublic(EmergencyContactBase):
    id: str
    user_id: str
    created_at: datetime
    updated_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


class IncidentCreate(BaseModel):
    title: str
    description: Optional[str] = None
    threat_level: Optional[str] = None
    evidence_url: Optional[str] = None
    fcm_token: Optional[str] = None
    media_type: Optional[str] = None
    media_size_bytes: Optional[int] = Field(default=None, ge=0)


class IncidentPublic(BaseModel):
    id: str
    user_id: str
    title: str
    description: Optional[str] = None
    threat_level: Optional[str] = None
    evidence_url: Optional[str] = None
    created_at: datetime
    updated_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


class DeviceRegisterRequest(BaseModel):
    device_name: str
    device_type: str


class DevicePublic(BaseModel):
    id: str
    user_id: str
    device_name: str
    device_type: str
    is_active: bool
    created_at: datetime
    last_seen: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


class DeviceHeartbeatRequest(BaseModel):
    battery_level: Optional[int] = Field(default=None, ge=0, le=100)
    signal_strength: Optional[int] = Field(default=None, ge=0, le=100)
    firmware_version: Optional[str] = None


class ProcessThreatRequest(BaseModel):
    device_id: str
    threat_type: str = Field(description="motion|voice|weapon|fused")
    confidence: float = Field(ge=0.0, le=1.0)
    summary: str
    details: dict[str, Any] = Field(default_factory=dict)
    location: Optional[dict[str, float]] = None


class HeartbeatRequest(BaseModel):
    timestamp: datetime
    threat_score: float = Field(ge=0.0, le=100.0)
    location: dict[str, float]


class EmergencyAlertRequest(BaseModel):
    incident_id: Optional[str] = None
    auto: bool = False
    severity: str = Field(default="high")
    summary: str
    location: dict[str, float]
    contacts: list[dict[str, Any]] = Field(default_factory=list)
    metadata: dict[str, Any] = Field(default_factory=dict)
