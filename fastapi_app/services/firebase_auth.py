from __future__ import annotations

import logging

from dataclasses import dataclass
from typing import Any, Optional

from fastapi import HTTPException, status


logger = logging.getLogger(__name__)

# Firebase mints tokens against Google's clock. A client or server running even
# a second behind will otherwise see a freshly-issued token rejected as "used
# too early", which shows up as intermittent, unreproducible sign-in failures.
# Google's own client libraries allow the same kind of leeway.
CLOCK_SKEW_TOLERANCE_SECONDS = 30


@dataclass
class FirebaseIdentity:
    uid: str
    email: str
    name: Optional[str]
    raw_claims: dict[str, Any]
    # Whether the identity provider itself vouches for the address. Google
    # sets this after its own confirmation, so it is a stronger assertion
    # than SafeHer's own emailed code, not a weaker one.
    email_verified: bool = False


def _verify_with_google(
    *, id_token: str, project_id: Optional[str], clock_skew_in_seconds: int
) -> Any:
    """Call Google's verifier.

    Split out from [verify_firebase_id_token] so the surrounding policy --
    skew tolerance, logging, synthetic addresses -- is testable without a
    network round-trip to Google's certificate endpoint.
    """
    try:
        from google.auth.transport import requests as google_requests
        from google.oauth2 import id_token as google_id_token
    except ModuleNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="google-auth is required for Firebase token verification",
        ) from exc

    return google_id_token.verify_firebase_token(
        id_token,
        google_requests.Request(),
        audience=project_id,
        clock_skew_in_seconds=clock_skew_in_seconds,
    )


def verify_firebase_id_token(*, id_token: str, project_id: Optional[str]) -> FirebaseIdentity:
    """Verify Firebase ID token and return normalized identity claims."""

    try:
        claims = _verify_with_google(
            id_token=id_token,
            project_id=project_id,
            clock_skew_in_seconds=CLOCK_SKEW_TOLERANCE_SECONDS,
        )
    except HTTPException:
        raise
    except Exception as exc:
        # The reason is logged but never returned: it can distinguish an expired
        # token from a wrong-audience one, which is useful to an attacker
        # probing the endpoint and useless to a legitimate client.
        logger.warning("Firebase ID token rejected: %s: %s", type(exc).__name__, exc)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Firebase ID token",
        ) from exc

    if not isinstance(claims, dict):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Firebase token claims",
        )

    email = str(claims.get("email") or "").strip().lower()
    uid = str(claims.get("uid") or claims.get("user_id") or "").strip()
    name = claims.get("name")

    if not uid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Firebase token missing user identifier",
        )

    if not email:
        # Phone and anonymous sign-ins carry no email claim, but the backend
        # keys accounts by address. Derive a stable synthetic one from the
        # Firebase uid, tagged with the provider so these accounts are
        # recognisable in the database rather than all looking like phone users.
        provider = str(
            claims.get("firebase", {}).get("sign_in_provider")
            or claims.get("provider_id")
            or "unknown"
        ).strip().lower()
        domain = {
            "phone": "phone.safeherapp.com",
            "anonymous": "anonymous.safeherapp.com",
        }.get(provider, "firebase.safeherapp.com")
        email = f"{uid}@{domain}"

    return FirebaseIdentity(
        uid=uid,
        email=email,
        name=str(name).strip() if isinstance(name, str) and name.strip() else None,
        raw_claims=claims,
        email_verified=bool(claims.get("email_verified", False)),
    )
