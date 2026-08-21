from functools import lru_cache
from pathlib import Path
from typing import Annotated, List, Optional

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


PROJECT_ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = PROJECT_ROOT / ".env"


class Settings(BaseSettings):
    # Core
    app_name: str = "SafeHer API"
    environment: str = "development"
    debug: bool = False
    log_level: str = "INFO"
    api_prefix: str = "/api/v1"
    api_host: str = "0.0.0.0"
    api_port: int = 5000
    enable_mqtt_worker: bool = True
    event_processor_url: str = "http://localhost:8080"

    # Database
    database_url: str = "sqlite:///./safeher.db"

    # Redis / MQTT
    redis_host: str = "localhost"
    redis_port: int = 6379
    redis_password: Optional[str] = None
    mqtt_host: str = "localhost"
    mqtt_port: int = 1883
    mqtt_username: Optional[str] = None
    mqtt_password: Optional[str] = None
    mqtt_tls_enabled: bool = False
    mqtt_tls_ca_path: Optional[str] = None
    mqtt_stale_after_seconds: int = 60

    # Auth / JWT
    jwt_secret_key: Optional[str] = None
    jwt_issuer: str = "safeher"
    jwt_audience: str = "safeher-clients"
    # SRS FR-AUTH-04: 15-minute access token, 30-day refresh token.
    access_token_expire_minutes: int = 15
    refresh_token_expire_days: int = 30
    # SRS FR-AUTH-07: 5 failed logins -> 15-minute lockout.
    max_failed_logins: int = 5
    login_lockout_minutes: int = 15
    # SRS FR-AUTH-08: GDPR Art. 17 erasure with a recovery window.
    account_deletion_grace_days: int = 30
    # SRS FR-AUTH-01: emailed OTP.
    email_otp_ttl_minutes: int = 10
    email_otp_max_attempts: int = 5

    # Email (OTP delivery)
    smtp_host: Optional[str] = None
    smtp_port: int = 587
    smtp_username: Optional[str] = None
    smtp_password: Optional[str] = None
    smtp_use_tls: bool = True
    # Implicit TLS (SMTPS). Left unset it follows the port, which is what
    # every mail provider means by 465 anyway — and saves one more setting
    # to get wrong. Set explicitly to override.
    smtp_use_ssl_override: Optional[bool] = None
    smtp_from_email: Optional[str] = None
    smtp_from_name: str = "SafeHer"
    # How long to wait on the SMTP socket.
    #
    # Ten seconds, not the twenty this used to hardcode, because the failure
    # this most often meets is a *blocked port* rather than a slow server —
    # and a blocked port does not refuse, it hangs until the timeout. At three
    # attempts per channel per contact, twenty seconds turned two contacts
    # into two minutes of a worker doing nothing. A real mail server answers
    # in well under ten.
    smtp_timeout_seconds: int = 10

    # --- Brevo (HTTPS email) --------------------------------------------
    # The channel that works where SMTP cannot.
    #
    # Render's free web services block outbound traffic on ports 25, 465 and
    # 587, which is every port SMTP speaks. The credentials are fine and the
    # code is correct; the platform simply refuses to route the packets, so
    # emergency email and contact verification both failed in production
    # while working perfectly from a laptop.
    #
    # Brevo delivers over ordinary HTTPS, which no such policy blocks, and its
    # free tier verifies an individual sender address rather than requiring a
    # domain you own — which is what rules OneSignal out for this project (see
    # `services/onesignal.py`). Set BREVO_API_KEY and email starts working
    # with no other change.
    brevo_api_key: Optional[str] = None
    # Left unset, verification is enforced exactly when OTPs can actually be
    # delivered. Forcing it on without SMTP would lock every new account out of
    # an app it just created, so the default follows deliverability rather than
    # guessing. Set explicitly to override.
    require_email_verification: Optional[bool] = None

    # Notifications.
    #
    # FCM v1 authenticates with a service-account JSON, not a server key.
    # The legacy key API this project used was decommissioned by Google and
    # its endpoint now 404s, so fcm_server_key is kept only so an existing
    # .env does not fail to load -- it is read by nothing.
    fcm_service_account_file: Optional[str] = None
    # The same credential as the file above, carried as a value instead of
    # a path -- the only form that works on a host with an ephemeral
    # filesystem. Accepts raw JSON or base64. Takes precedence when both
    # are set, so a deployed environment cannot be silently overridden by
    # a stale path inherited from a developer's .env.
    fcm_service_account_json: Optional[str] = None
    fcm_server_key: Optional[str] = None
    # SMS. Note that OneSignal is not an alternative here: its free-tier
    # SMS trial works by connecting your own Twilio account, and its paid
    # SMS is billed per message. Whichever route, SMS costs money.
    twilio_account_sid: Optional[str] = None
    twilio_auth_token: Optional[str] = None
    twilio_from_number: Optional[str] = None

    # Email, via OneSignal's free tier (10,000 sends/month at time of
    # writing). This is the emergency channel that costs nothing, so it is
    # the one a project without a sponsor can actually rely on.
    onesignal_app_id: Optional[str] = None
    onesignal_api_key: Optional[str] = None

    # Storage
    cloudinary_cloud_name: Optional[str] = None
    cloudinary_api_key: Optional[str] = None
    cloudinary_api_secret: Optional[str] = None
    firebase_storage_bucket: Optional[str] = None
    firebase_project_id: Optional[str] = None
    cloudinary_upload_preset: Optional[str] = None
    media_max_size_bytes: int = 10 * 1024 * 1024

    # Emergency evidence (SRS FR-EMG-06/07). Stored on the project's own
    # infrastructure by default -- no third-party account required -- and
    # always encrypted at rest. See services/evidence_store.py.
    evidence_storage_dir: str = "./evidence_store"
    # Optional. Unset, a key is derived from JWT_SECRET_KEY, so evidence is
    # never written in the clear just because nobody configured this.
    evidence_encryption_key: Optional[str] = None
    evidence_max_size_bytes: int = 25 * 1024 * 1024
    # Where a share link points. Must be reachable by the recipient,
    # who is not on this machine -- the localhost default only works
    # for local testing and has to be set before any real deployment.
    public_base_url: str = "http://127.0.0.1:5000/api/v1"

    # AI
    openai_api_key: Optional[str] = None

    # AI incident summaries (FR-RPT-01). Gemini has a usable free tier,
    # which is what makes this requirement reachable at all here.
    gemini_api_key: Optional[str] = None
    # An alias rather than a pinned version: gemini-2.5-flash was retired
    # for new keys mid-project and started answering 404. An alias moves
    # with Google; the cost is that behaviour can shift under you, which is
    # acceptable for a summary and would not be for anything load-bearing.
    gemini_model: str = "gemini-flash-latest"

    # Maps
    google_maps_api_key: Optional[str] = None

    # CORS
    # NoDecode: pydantic-settings otherwise tries to JSON-parse env-sourced
    # List[str] values before any validator runs, which rejects the plain
    # comma-separated format documented in .env.example (e.g.
    # "http://a,http://b"). NoDecode defers to split_allow_origins below.
    allow_origins: Annotated[List[str], NoDecode] = [
        "http://localhost:3000",
        "http://localhost:5173",
        "http://localhost:8080",
    ]
    allow_origin_regex: Optional[str] = None

    model_config = SettingsConfigDict(
        env_file=ENV_FILE,
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    @model_validator(mode="after")
    def validate_secrets(self):
        env = self.environment.lower()
        if env in {"production", "staging"}:
            if not self.jwt_secret_key or self.jwt_secret_key == "change-me":
                raise ValueError(
                    "JWT_SECRET_KEY must be set to a strong value in staging/production"
                )
        if env == "development" and not self.allow_origin_regex:
            self.allow_origin_regex = r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"
        return self

    @property
    def smtp_configured(self) -> bool:
        return bool(self.smtp_host and self.smtp_from_email)

    @property
    def brevo_configured(self) -> bool:
        # The sender address is Brevo's, but it is the same address SMTP
        # sends from, so it is read from one setting rather than two that can
        # drift apart.
        return bool(self.brevo_api_key and self.smtp_from_email)

    @property
    def email_configured(self) -> bool:
        """Whether *any* email channel can send.

        Used wherever the question is "can this reach a contact by email",
        which is not the same as "is SMTP set up" now that there are two
        transports.
        """
        return self.brevo_configured or self.smtp_configured

    @property
    def smtp_use_ssl(self) -> bool:
        if self.smtp_use_ssl_override is not None:
            return self.smtp_use_ssl_override
        return self.smtp_port == 465

    @property
    def email_verification_required(self) -> bool:
        if self.require_email_verification is not None:
            return self.require_email_verification
        # Follows deliverability, not SMTP specifically: an HTTPS channel can
        # send the OTP just as well, and requiring verification the app cannot
        # deliver would lock every new account out of itself.
        return self.email_configured

    @field_validator("api_prefix", mode="before")
    @classmethod
    def normalize_api_prefix(cls, value):
        if not isinstance(value, str):
            return "/api/v1"
        prefix = value.strip()
        if not prefix:
            return "/api/v1"
        if not prefix.startswith("/"):
            prefix = f"/{prefix}"
        return prefix.rstrip("/")

    @field_validator("environment", mode="before")
    @classmethod
    def normalize_environment(cls, value):
        if not isinstance(value, str):
            return "development"
        env = value.strip().lower()
        if env in {"dev", "local"}:
            return "development"
        if env in {"prod"}:
            return "production"
        if env in {"stage"}:
            return "staging"
        return env or "development"

    @field_validator("allow_origins", mode="before")
    @classmethod
    def split_allow_origins(cls, v):
        if isinstance(v, str):
            return [origin.strip() for origin in v.split(",") if origin.strip()]
        return v


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()