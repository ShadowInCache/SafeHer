from datetime import datetime
from typing import Any, Optional
from uuid import uuid4

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator


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
    # SRS FR-EMG-02. Bounded because a threshold of 0 would auto-dispatch on
    # every reading, and one above 1.0 could never be reached -- silently
    # disabling the alarm the setting exists to control.
    threat_threshold: Optional[float] = Field(default=None, ge=0.05, le=1.0)


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
    # SRS FR-EMG-02 -- the score at which SafeHer raises the alarm unasked.
    threat_threshold: float = 0.75
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
    # SRS FR-EMG-10. Null means nobody at this address has confirmed a code
    # — the contact is still notified, but the app flags it.
    verified_at: Optional[datetime] = None
    created_at: datetime
    updated_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


class ContactVerifyRequest(BaseModel):
    code: str = Field(min_length=4, max_length=10)


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

    # Set only by POST /alerts/emergency, which fans the alert out to the
    # user's emergency contacts (FR-EMG-04). None on every other endpoint
    # that returns an incident, where no dispatch was attempted — which is
    # a different fact from "attempted and reached nobody" (0).
    # SRS FR-RPT-01. Machine-written; the client labels it as such so it is
    # never read as a human account of what happened.
    ai_summary: Optional[str] = None
    ai_summary_generated_at: Optional[datetime] = None

    contacts_total: Optional[int] = None
    contacts_notified: Optional[int] = None
    # Ids of the contacts a channel actually accepted. The client marks
    # exactly these in the UI — an aggregate count alone would force it to
    # guess *which* contacts were reached, and guessing wrong on this screen
    # tells a woman in danger that help is coming when it is not.
    contacts_reached: Optional[list[str]] = None
    # Contacts every channel refused. Sent separately from "absent from
    # `contacts_reached`" because until the fan-out finishes those are the
    # same list, and the screen must not show a contact still being tried as
    # one nobody could reach.
    contacts_failed: Optional[list[str]] = None

    # "in_progress" while the background fan-out is still running,
    # "complete" once it has finished, "failed" if it crashed. None means no
    # dispatch was ever attempted for this incident.
    dispatch_status: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)

    @field_validator("contacts_reached", "contacts_failed", mode="before")
    @classmethod
    def _decode_id_list(cls, value: Any) -> Any:
        """Accepts the JSON text the column stores, or a list from a router.

        `Incident.contacts_reached` is a Text column holding a JSON array,
        because it is a snapshot of one dispatch rather than a relation. That
        means `model_validate(incident)` hands this field a `str`, and without
        this it fails validation — which took out every endpoint that returns
        an incident, not just the dispatch ones.

        A malformed value degrades to an empty list rather than raising. The
        alternative is a 500 on the incident list because one row's audit
        column is unparseable.
        """
        if value is None or isinstance(value, list):
            return value
        if isinstance(value, str):
            if not value:
                return None
            import json as _json

            try:
                parsed = _json.loads(value)
            except ValueError:
                return []
            return parsed if isinstance(parsed, list) else []
        return value


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


class ModelScoresRequest(BaseModel):
    """One synchronised read from the wearables' models (SRS §6.2).

    Every modality is optional and defaults to `None`, never 0.0. A missing
    sensor is excluded from the fusion and the remaining weights are
    renormalised; a zero would claim the sensor looked and saw calm, which
    with no camera attached would cap the achievable score at 0.75 and
    quietly disable the automatic alarm.
    """

    device_id: Optional[str] = None
    timestamp: Optional[datetime] = None

    motion_score: Optional[float] = Field(
        default=None, ge=0.0, le=1.0, description="XGBoost over glove accel + gyro"
    )
    audio_score: Optional[float] = Field(
        default=None, ge=0.0, le=1.0, description="CNN+LSTM over glasses microphone"
    )
    vision_score: Optional[float] = Field(
        default=None, ge=0.0, le=1.0, description="YOLOv8 over glasses camera"
    )
    weapon_confidence: float = Field(
        default=0.0, ge=0.0, le=1.0, description="YOLOv8 weapon class; boosts above 0.70 per §6.2"
    )
    weapon_label: Optional[str] = Field(
        default=None,
        max_length=40,
        description="What YOLOv8 identified -- 'a knife', 'a gun', 'a rod'. Reported verbatim in the incident, so it is length-capped and escaped downstream.",
    )
    heart_rate_bpm: Optional[float] = Field(
        default=None, ge=20.0, le=250.0, description="Glove pulse sensor; a booster, not a weight"
    )
    location: Optional[dict[str, float]] = None
    in_high_risk_zone: bool = False


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
