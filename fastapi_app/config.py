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

    # Database / Supabase
    database_url: str = "sqlite:///./safeher.db"
    supabase_url: Optional[str] = None
    supabase_publishable_key: Optional[str] = None
    supabase_secret_key: Optional[str] = None

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
    smtp_from_email: Optional[str] = None
    smtp_from_name: str = "SafeHer"
    # Left unset, verification is enforced exactly when OTPs can actually be
    # delivered. Forcing it on without SMTP would lock every new account out of
    # an app it just created, so the default follows deliverability rather than
    # guessing. Set explicitly to override.
    require_email_verification: Optional[bool] = None

    # Notifications
    fcm_server_key: Optional[str] = None
    twilio_account_sid: Optional[str] = None
    twilio_auth_token: Optional[str] = None
    twilio_from_number: Optional[str] = None

    # Storage
    cloudinary_cloud_name: Optional[str] = None
    cloudinary_api_key: Optional[str] = None
    cloudinary_api_secret: Optional[str] = None
    firebase_storage_bucket: Optional[str] = None
    firebase_project_id: Optional[str] = None
    cloudinary_upload_preset: Optional[str] = None
    media_max_size_bytes: int = 10 * 1024 * 1024

    # AI
    openai_api_key: Optional[str] = None

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
    def email_verification_required(self) -> bool:
        if self.require_email_verification is not None:
            return self.require_email_verification
        return self.smtp_configured

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