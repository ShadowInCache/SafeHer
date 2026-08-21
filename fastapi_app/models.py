from datetime import datetime
from uuid import uuid4

from sqlalchemy import Boolean, Column, DateTime, Float, ForeignKey, Integer, String, Text

from fastapi_app.db import Base


def _utcnow() -> datetime:
    return datetime.utcnow()


class User(Base):
    __tablename__ = "users"

    id = Column(String, primary_key=True, default=lambda: str(uuid4()))
    email = Column(String, unique=True, index=True, nullable=False)
    password_hash = Column(String, nullable=False)
    full_name = Column(String, nullable=True)
    phone = Column(String, nullable=True)
    avatar_url = Column(String, nullable=True)
    push_notifications = Column(Boolean, nullable=False, default=True)
    sms_notifications = Column(Boolean, nullable=False, default=False)
    email_notifications = Column(Boolean, nullable=False, default=True)
    location_sharing = Column(Boolean, nullable=False, default=True)
    role = Column(String, nullable=False, default="user")
    is_active = Column(Boolean, nullable=False, default=True)

    # SRS FR-AUTH-01 -- account is unverified until the emailed OTP is entered.
    is_verified = Column(Boolean, nullable=False, default=False)

    # SRS FR-EMG-02 -- the smoothed threat score at which SafeHer raises the
    # alarm without being asked. Lives here rather than only in the app: the
    # decision is taken server-side, so the preference has to be too.
    threat_threshold = Column(Float, nullable=False, default=0.75, server_default="0.75")

    # SRS FR-AUTH-07 -- 5 failed logins trigger a timed lockout.
    failed_login_attempts = Column(Integer, nullable=False, default=0)
    locked_until = Column(DateTime, nullable=True)

    # SRS FR-AUTH-06 -- tokens issued before this instant are rejected, which
    # revokes every existing session across all devices without needing a
    # server-side blacklist of individual JWTs.
    tokens_valid_from = Column(DateTime, nullable=False, default=_utcnow)

    # SRS FR-AUTH-08 -- deletion is scheduled, not immediate, so the user can
    # still change their mind inside the grace period.
    deletion_requested_at = Column(DateTime, nullable=True)

    created_at = Column(DateTime, nullable=False, default=_utcnow)
    updated_at = Column(DateTime, nullable=False, default=_utcnow, onupdate=_utcnow)


class EmailVerificationCode(Base):
    """A single-use OTP emailed to prove ownership of an address.

    Only the hash is stored: a leaked database must not yield working codes.
    """

    __tablename__ = "email_verification_codes"

    id = Column(String, primary_key=True, default=lambda: str(uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    code_hash = Column(String, nullable=False)
    # Separates "prove you own this address" from "let me reset my password".
    # Without it, a code emailed for one purpose would be redeemable for the
    # other, so an unverified-email OTP could change the account password.
    purpose = Column(String, nullable=False, default="email_verification")
    expires_at = Column(DateTime, nullable=False)
    attempts = Column(Integer, nullable=False, default=0)
    consumed_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, nullable=False, default=_utcnow)


class Incident(Base):
    __tablename__ = "incidents"

    id = Column(String, primary_key=True, default=lambda: str(uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    title = Column(String, nullable=False)
    description = Column(String, nullable=True)
    threat_level = Column(String, nullable=True)
    evidence_url = Column(String, nullable=True)

    # SRS FR-RPT-01. Machine-written, and labelled as such everywhere it is
    # shown -- it must never be mistaken for a human account or evidence.
    ai_summary = Column(Text, nullable=True)
    ai_summary_generated_at = Column(DateTime, nullable=True)

    # SRS FR-EMG-02 -- raised by the system, not by a tap. Durable because
    # the §6.2 deduplication window is measured against it, and a window
    # held only in memory would not survive a restart mid-emergency.
    auto_dispatched = Column(Boolean, nullable=False, default=False, server_default="0")

    # SRS §6.1 -- what each model observed, so the report can say why SafeHer
    # decided she was in danger rather than only that it did. Nullable per
    # modality: a sensor that did not report is not one that reported calm,
    # and a report that cannot tell those apart is misleading about coverage.
    motion_score = Column(Float, nullable=True)
    audio_score = Column(Float, nullable=True)
    vision_score = Column(Float, nullable=True)
    weapon_confidence = Column(Float, nullable=True)

    # The value actually compared against the threshold, after §6.2 fusion,
    # smoothing and context boosters -- not the raw weighted sum.
    fused_score = Column(Float, nullable=True)
    threshold_used = Column(Float, nullable=True)

    # Free text, deliberately. The shape of a detection belongs to the models,
    # and none is trained yet; committing to columns for "weapon class" and
    # "trigger words" now would be guessing at a schema, and a wrong guess is
    # a migration during a live deployment.
    detections = Column(Text, nullable=True)

    # SRS FR-EMG-01/04 -- the state of the contact fan-out, which now runs in
    # the background so the SOS response is not held behind it.
    #
    # NULL means no dispatch was ever attempted for this incident. That is a
    # different fact from "attempted and reached nobody", and the two must not
    # collapse: one is an incident filed by some other route, the other is the
    # worst outcome the product has.
    dispatch_status = Column(String, nullable=True)
    contacts_total = Column(Integer, nullable=True)
    contacts_notified = Column(Integer, nullable=True)
    # JSON arrays of contact ids. A snapshot of one dispatch attempt, not a
    # fact about the contacts themselves -- see migration 0013 for why this
    # is not modelled as rows.
    contacts_reached = Column(Text, nullable=True)
    contacts_failed = Column(Text, nullable=True)
    dispatch_completed_at = Column(DateTime, nullable=True)

    created_at = Column(DateTime, nullable=False, default=_utcnow)
    updated_at = Column(DateTime, nullable=False, default=_utcnow, onupdate=_utcnow)


class IncidentShare(Base):
    """A time-limited, revocable read-only link to one incident.

    SRS FR-RPT-06. This is how an incident reaches someone who has no
    SafeHer account -- a police officer, a lawyer, a parent -- without
    handing them the owner's credentials.

    Only the hash of the token is stored, for the same reason as every other
    secret here: a leaked database must not yield working links to
    recordings of people in danger.
    """

    __tablename__ = "incident_shares"

    id = Column(String, primary_key=True, default=lambda: str(uuid4()))
    incident_id = Column(String, ForeignKey("incidents.id", ondelete="CASCADE"), nullable=False, index=True)
    token_hash = Column(String, nullable=False, unique=True, index=True)
    expires_at = Column(DateTime, nullable=False)
    # Set when the owner revokes the link early. Kept rather than deleted so
    # a revoked link can be told apart from one that never existed.
    revoked_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, nullable=False, default=_utcnow)


class Device(Base):
    __tablename__ = "devices"

    id = Column(String, primary_key=True, default=lambda: str(uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    device_type = Column(String, nullable=False)
    device_name = Column(String, nullable=False)
    auth_secret = Column(String, nullable=False)
    is_active = Column(Boolean, nullable=False, default=True)
    last_seen = Column(DateTime, nullable=True)
    battery_level = Column(Integer, nullable=True)
    signal_strength = Column(Integer, nullable=True)
    firmware_version = Column(String, nullable=True)
    created_at = Column(DateTime, nullable=False, default=_utcnow)
    updated_at = Column(DateTime, nullable=False, default=_utcnow, onupdate=_utcnow)


class Location(Base):
    __tablename__ = "locations"

    id = Column(String, primary_key=True, default=lambda: str(uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    device_id = Column(String, ForeignKey("devices.id", ondelete="SET NULL"), nullable=True)
    incident_id = Column(String, ForeignKey("incidents.id", ondelete="SET NULL"), nullable=True)
    # Safe Journey breadcrumbs reuse this table rather than introducing a
    # parallel location store — one source of truth for "where was the user".
    journey_id = Column(String, ForeignKey("safe_journeys.id", ondelete="CASCADE"), nullable=True, index=True)
    lat = Column(Float, nullable=False)
    lng = Column(Float, nullable=False)
    accuracy = Column(Float, nullable=True)
    captured_at = Column(DateTime, nullable=False, default=_utcnow)
    created_at = Column(DateTime, nullable=False, default=_utcnow)


class Media(Base):
    __tablename__ = "media"

    id = Column(String, primary_key=True, default=lambda: str(uuid4()))
    incident_id = Column(String, ForeignKey("incidents.id", ondelete="CASCADE"), nullable=False)
    url = Column(String, nullable=False)
    media_type = Column(String, nullable=False)
    size_bytes = Column(Integer, nullable=True)
    created_at = Column(DateTime, nullable=False, default=_utcnow)


class NotificationLog(Base):
    __tablename__ = "notification_logs"

    id = Column(String, primary_key=True, default=lambda: str(uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    device_id = Column(String, ForeignKey("devices.id", ondelete="SET NULL"), nullable=True)
    token = Column(String, nullable=True)
    channel = Column(String, nullable=False)
    status = Column(String, nullable=False)
    payload = Column(Text, nullable=True)
    created_at = Column(DateTime, nullable=False, default=_utcnow)


class FcmToken(Base):
    __tablename__ = "fcm_tokens"

    id = Column(String, primary_key=True, default=lambda: str(uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    device_id = Column(String, ForeignKey("devices.id", ondelete="CASCADE"), nullable=True)
    token = Column(String, nullable=False, unique=True)
    created_at = Column(DateTime, nullable=False, default=_utcnow)


class EmergencyContact(Base):
    __tablename__ = "emergency_contacts"

    id = Column(String, primary_key=True, default=lambda: str(uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    name = Column(String, nullable=False)
    phone = Column(String, nullable=False)
    email = Column(String, nullable=True)
    relationship = Column(String, nullable=True)
    priority = Column(Integer, nullable=False, default=1)

    # SRS FR-EMG-10. Null until someone at this address has proved they
    # received a code. An unverified contact is still notified in an
    # emergency -- see services/emergency_dispatch.py for why -- but the app
    # flags it, because the commonest reason for a contact never hearing
    # from SafeHer is a typo nobody noticed.
    verified_at = Column(DateTime, nullable=True)
    # Only the hash, matching email_verification_codes: a leaked database
    # must not yield working codes.
    verification_code_hash = Column(String, nullable=True)
    verification_expires_at = Column(DateTime, nullable=True)
    verification_attempts = Column(Integer, nullable=False, default=0)

    created_at = Column(DateTime, nullable=False, default=_utcnow)
    updated_at = Column(DateTime, nullable=False, default=_utcnow, onupdate=_utcnow)

    @property
    def is_verified(self) -> bool:
        return self.verified_at is not None


class SafeJourney(Base):
    """A user-initiated trip with a deadline. While it is `active` the app
    posts real GPS breadcrumbs (into `locations`, tagged with `journey_id`)
    and the chosen contacts can be notified. If the deadline passes without
    the user confirming arrival the journey becomes `overdue` and the
    escalation policy in `services/journey_escalation.py` runs.
    """

    __tablename__ = "safe_journeys"

    id = Column(String, primary_key=True, default=lambda: str(uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    destination_label = Column(String, nullable=False)
    destination_lat = Column(Float, nullable=True)
    destination_lng = Column(Float, nullable=True)
    expected_duration_minutes = Column(Integer, nullable=False)
    check_in_interval_minutes = Column(Integer, nullable=True)
    # active | arrived | cancelled | overdue
    status = Column(String, nullable=False, default="active", index=True)
    started_at = Column(DateTime, nullable=False, default=_utcnow)
    expected_arrival_at = Column(DateTime, nullable=False)
    last_check_in_at = Column(DateTime, nullable=True)
    ended_at = Column(DateTime, nullable=True)
    escalated_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, nullable=False, default=_utcnow)
    updated_at = Column(DateTime, nullable=False, default=_utcnow, onupdate=_utcnow)


class JourneyParticipant(Base):
    """Which of the user's existing emergency contacts are watching a journey.
    References `emergency_contacts` rather than duplicating name/phone, so
    editing a contact updates every journey that includes them.
    """

    __tablename__ = "journey_participants"

    id = Column(String, primary_key=True, default=lambda: str(uuid4()))
    journey_id = Column(String, ForeignKey("safe_journeys.id", ondelete="CASCADE"), nullable=False, index=True)
    contact_id = Column(String, ForeignKey("emergency_contacts.id", ondelete="CASCADE"), nullable=False)
    created_at = Column(DateTime, nullable=False, default=_utcnow)


class SafetyPin(Base):
    """Hashed cancel-PIN. Stored with the same passlib context used for
    account passwords — never in plaintext, never in device preferences.
    """

    __tablename__ = "safety_pins"

    id = Column(String, primary_key=True, default=lambda: str(uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True, index=True)
    pin_hash = Column(String, nullable=False)
    failed_attempts = Column(Integer, nullable=False, default=0)
    locked_until = Column(DateTime, nullable=True)
    created_at = Column(DateTime, nullable=False, default=_utcnow)
    updated_at = Column(DateTime, nullable=False, default=_utcnow, onupdate=_utcnow)


class UserSafetyPreferences(Base):
    """Opt-in switches for the phone-side safety triggers. Defaults are all
    off for anything that can raise an alarm — a trigger the user never chose
    to enable must never fire.
    """

    __tablename__ = "user_safety_preferences"

    id = Column(String, primary_key=True, default=lambda: str(uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True, index=True)
    shake_trigger_enabled = Column(Boolean, nullable=False, default=False)
    # 1 = least sensitive (hardest to trigger), 3 = most sensitive
    shake_sensitivity = Column(Integer, nullable=False, default=2)
    voice_commands_enabled = Column(Boolean, nullable=False, default=False)
    require_pin_to_cancel = Column(Boolean, nullable=False, default=False)
    journey_auto_share_location = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime, nullable=False, default=_utcnow)
    updated_at = Column(DateTime, nullable=False, default=_utcnow, onupdate=_utcnow)
