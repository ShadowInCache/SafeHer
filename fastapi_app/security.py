from datetime import datetime, timedelta, timezone
from typing import Callable, Optional
from uuid import uuid4

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.config import Settings, get_settings
from fastapi_app.db import get_session
from fastapi_app.repositories import users as user_repo
from fastapi_app.schemas import TokenPayload, UserPublic

# Use PBKDF2 as primary algorithm for stability across environments while
# retaining bcrypt verify compatibility for legacy hashes.
pwd_context = CryptContext(schemes=["pbkdf2_sha256", "bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        return pwd_context.verify(plain_password, hashed_password)
    except ValueError:
        return False


def get_password_hash(password: str) -> str:
    return pwd_context.hash(password)


def create_access_token(*, subject: str, role: str, settings: Settings, expires_delta: Optional[timedelta] = None) -> str:
    if expires_delta is None:
        expires_delta = timedelta(minutes=settings.access_token_expire_minutes)

    now = datetime.now(timezone.utc)
    expire = now + expires_delta
    to_encode = {
        "exp": expire,
        "iat": now,
        "sub": subject,
        "role": role,
        "iss": settings.jwt_issuer,
        "aud": settings.jwt_audience,
        "jti": str(uuid4()),
        "type": "access",
    }
    encoded_jwt = jwt.encode(to_encode, settings.jwt_secret_key, algorithm="HS256")
    return encoded_jwt


def create_refresh_token(*, subject: str, role: str, settings: Settings) -> str:
    now = datetime.now(timezone.utc)
    expire = now + timedelta(days=settings.refresh_token_expire_days)
    to_encode = {
        "exp": expire,
        "iat": now,
        "sub": subject,
        "role": role,
        "iss": settings.jwt_issuer,
        "aud": settings.jwt_audience,
        "jti": str(uuid4()),
        "type": "refresh",
    }
    return jwt.encode(to_encode, settings.jwt_secret_key, algorithm="HS256")


def create_ws_ticket(*, subject: str, role: str, settings: Settings) -> str:
    """A short-lived credential for opening the alert WebSocket.

    **Why this exists.** A browser cannot set headers on a WebSocket
    handshake -- the JavaScript API has no place to put them -- so the
    credential has to travel in the URL. A URL is the one place a
    credential should never be: query strings are written to proxy and
    access logs, kept in history, and forwarded in referrers.

    The answer is not to move the access token, but to send something else
    entirely. This ticket is obtained with a normal `Authorization` header,
    lives for [Settings.ws_ticket_expire_seconds] and opens nothing but the
    alert feed -- `decode_token` refuses it anywhere `access` is expected.
    By the time a log line containing one is read by anybody, it has been
    useless for a long while.

    Deliberately a signed JWT rather than a random string in a server-side
    table. A stored ticket would be single-use, which is stricter, but it
    would live in one process's memory: minted on one worker and redeemed
    on another, it would simply fail, and the reconnect loop would look
    like a flaky network to the one person who needs the live feed.
    """
    now = datetime.now(timezone.utc)
    to_encode = {
        "exp": now + timedelta(seconds=settings.ws_ticket_expire_seconds),
        "iat": now,
        "sub": subject,
        "role": role,
        "iss": settings.jwt_issuer,
        "aud": settings.jwt_audience,
        "jti": str(uuid4()),
        "type": "ws_ticket",
    }
    return jwt.encode(to_encode, settings.jwt_secret_key, algorithm="HS256")


def decode_token(token: str, settings: Settings, expected_type: str = "access") -> TokenPayload:
    try:
        payload = jwt.decode(token, settings.jwt_secret_key, algorithms=["HS256"], audience=settings.jwt_audience, issuer=settings.jwt_issuer)
        if payload.get("type") != expected_type:
            raise JWTError("Invalid token type")
        return TokenPayload(
            sub=payload["sub"],
            role=payload.get("role", "user"),
            exp=payload["exp"],
            iat=payload.get("iat"),
            type=payload.get("type", "access"),
        )
    except JWTError as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Could not validate credentials") from e


def ensure_token_not_revoked(payload: TokenPayload, user) -> None:
    """Reject tokens minted before the user's last credential change.

    Tokens issued at exactly `tokens_valid_from` are kept: the token a password
    change hands back is stamped in the same second as the revocation cutoff,
    and rounding it out would log the user out of the device they just used to
    change their password.
    """
    valid_from = getattr(user, "tokens_valid_from", None)
    if valid_from is None or payload.iat is None:
        return

    issued_at = datetime.fromtimestamp(payload.iat, tz=timezone.utc).replace(tzinfo=None)
    if issued_at < valid_from.replace(microsecond=0):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session expired, please sign in again",
        )


async def get_current_user(
    token: str = Depends(oauth2_scheme),
    settings: Settings = Depends(get_settings),
    session: AsyncSession = Depends(get_session),
) -> UserPublic:
    payload = decode_token(token, settings, expected_type="access")
    user = await user_repo.get_by_email(session, payload.sub)
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    if not getattr(user, "is_active", True):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Inactive user")

    ensure_token_not_revoked(payload, user)

    return UserPublic.model_validate(user)


def require_roles(*roles: str) -> Callable[[UserPublic], UserPublic]:
    allowed = {role.lower() for role in roles}

    def _dependency(current_user: UserPublic = Depends(get_current_user)) -> UserPublic:
        if allowed and current_user.role.lower() not in allowed:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Insufficient permissions",
            )
        return current_user

    return _dependency
