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
    phone: Optional[str] = Field(default=None, max_length=32)


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserUpdate(BaseModel):
    full_name: Optional[str] = Field(default=None, max_length=120)
    phone: Optional[str] = Field(default=None, max_length=32)
    avatar_url: Optional[str] = None
    push_notifications: Optional[bool] = None
    sms_notifications: Optional[bool] = None
    email_notifications: Optional[bool] = None
    location_sharing: Optional[bool] = None


class UserPublic(UserBase):
    id: str = Field(default_factory=lambda: str(uuid4()))
    full_name: Optional[str] = None
    phone: Optional[str] = None
    avatar_url: Optional[str] = None
    push_notifications: bool = True
    sms_notifications: bool = False
    email_notifications: bool = True
    location_sharing: bool = True
    is_verified: bool = True
    deletion_requested_at: Optional[datetime] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


class Token(BaseModel):
    access_token: str
    refresh_token: Optional[str] = None
    token_type: str = "bearer"


class RegistrationResult(BaseModel):
    """Result of a sign-up.

    `verification_required` tells the client whether to route to the OTP screen
    or straight into the app, so the decision lives with the server that knows
    whether email delivery is configured.
    """

    user: "UserPublic"
    verification_required: bool
    verification_sent: bool
    # Populated only in development with no SMTP configured, so local sign-up
    # is not blocked on a mail server. Never populated once SMTP is set up.
    debug_code: Optional[str] = None


class EmailVerificationRequest(BaseModel):
    email: EmailStr
    code: str = Field(min_length=4, max_length=10)


class ResendVerificationRequest(BaseModel):
    email: EmailStr


class PasswordChangeRequest(BaseModel):
    current_password: str
    new_password: str = Field(min_length=8)


class PasswordResetRequest(BaseModel):
    email: EmailStr


class PasswordResetConfirmRequest(BaseModel):
    email: EmailStr
    code: str = Field(min_length=4, max_length=10)
    new_password: str = Field(min_length=8)


class AccountDeletionResponse(BaseModel):
    deletion_requested_at: datetime
    purge_scheduled_for: datetime
    grace_period_days: int


class TokenPayload(BaseModel):
    sub: str
    role: str
    exp: int
    type: str = "access"
    # Issued-at, compared against the user's `tokens_valid_from` to honour
    # password-change revocation (SRS FR-AUTH-06).
    iat: Optional[int] = None


class TokenRefreshRequest(BaseModel):
    refresh_token: str


class FirebaseTokenExchangeRequest(BaseModel):
    id_token: str = Field(min_length=10)
    role: str = Field(default="user")
    full_name: Optional[str] = None
    # Firebase only holds displayName/email/photoURL. The phone captured
    # during sign-up exists nowhere else, so the client sends it here or the
    # profile is provisioned without it.
    phone: Optional[str] = Field(default=None, max_length=32)
    avatar_url: Optional[str] = None


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
    # Populated by the router from a joined Location row when one exists
    # for this incident — not an ORM-mapped attribute on Incident itself,
    # since one incident could in principle have multiple location pings.
    # None means no location was ever captured for this incident, not 0,0.
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    location_accuracy: Optional[float] = None

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
    battery_level: Optional[int] = None
    signal_strength: Optional[int] = None
    firmware_version: Optional[str] = None

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


# --------------------------------------------------------------- safety features


class SafetyPinSetRequest(BaseModel):
    pin: str = Field(min_length=4, max_length=8, pattern=r"^\d+$")
    current_pin: Optional[str] = Field(default=None, min_length=4, max_length=8)


class SafetyPinVerifyRequest(BaseModel):
    pin: str = Field(min_length=4, max_length=8)


class SafetyPinStatus(BaseModel):
    is_set: bool
    is_locked: bool = False
    locked_until: Optional[datetime] = None


class SafetyPinVerifyResponse(BaseModel):
    valid: bool
    attempts_remaining: Optional[int] = None
    locked_until: Optional[datetime] = None


class SafetyPreferences(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    shake_trigger_enabled: bool = False
    shake_sensitivity: int = Field(default=2, ge=1, le=3)
    voice_commands_enabled: bool = False
    require_pin_to_cancel: bool = False
    journey_auto_share_location: bool = True


class SafetyPreferencesUpdate(BaseModel):
    shake_trigger_enabled: Optional[bool] = None
    shake_sensitivity: Optional[int] = Field(default=None, ge=1, le=3)
    voice_commands_enabled: Optional[bool] = None
    require_pin_to_cancel: Optional[bool] = None
    journey_auto_share_location: Optional[bool] = None


class NearbyPlace(BaseModel):
    id: str
    name: str
    category: str
    latitude: float
    longitude: float
    distance_metres: int
    phone: Optional[str] = None
    address: Optional[str] = None
    open_hours: Optional[str] = None


class JourneyCreateRequest(BaseModel):
    destination_label: str = Field(min_length=1, max_length=200)
    destination_lat: Optional[float] = Field(default=None, ge=-90, le=90)
    destination_lng: Optional[float] = Field(default=None, ge=-180, le=180)
    expected_duration_minutes: int = Field(ge=1, le=24 * 60)
    check_in_interval_minutes: Optional[int] = Field(default=None, ge=1, le=24 * 60)
    contact_ids: list[str] = Field(default_factory=list)


class JourneyLocationRequest(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy_metres: Optional[float] = Field(default=None, ge=0)


class JourneyBreadcrumb(BaseModel):
    latitude: float
    longitude: float
    accuracy_metres: Optional[float] = None
    captured_at: datetime


class JourneyPublic(BaseModel):
    id: str
    destination_label: str
    destination_lat: Optional[float] = None
    destination_lng: Optional[float] = None
    expected_duration_minutes: int
    check_in_interval_minutes: Optional[int] = None
    status: str
    started_at: datetime
    expected_arrival_at: datetime
    last_check_in_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None
    contact_ids: list[str] = Field(default_factory=list)
