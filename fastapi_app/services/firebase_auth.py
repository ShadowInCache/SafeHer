from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Optional

from fastapi import HTTPException, status


@dataclass
class FirebaseIdentity:
    uid: str
    email: str
    name: Optional[str]
    raw_claims: dict[str, Any]


def verify_firebase_id_token(*, id_token: str, project_id: Optional[str]) -> FirebaseIdentity:
    """Verify Firebase ID token and return normalized identity claims."""

    try:
        from google.auth.transport import requests as google_requests
        from google.oauth2 import id_token as google_id_token
    except ModuleNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="google-auth is required for Firebase token verification",
        ) from exc

    try:
        request_adapter = google_requests.Request()
        claims = google_id_token.verify_firebase_token(
            id_token,
            request_adapter,
            audience=project_id,
        )
    except Exception as exc:
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
        # Phone-auth users may not have an email claim; derive a stable identity.
        email = f"{uid}@phone.safeherapp.com"

    return FirebaseIdentity(
        uid=uid,
        email=email,
        name=str(name).strip() if isinstance(name, str) and name.strip() else None,
        raw_claims=claims,
    )
