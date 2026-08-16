"""Push notifications over FCM HTTP v1.

**Why this was rewritten.** The previous implementation posted to
`https://fcm.googleapis.com/fcm/send` with an `Authorization: key=<server
key>` header. That is the legacy FCM API, and Google decommissioned it — the
endpoint now answers 404 to everything, which was verified against the live
service rather than assumed. Every push this app sent was going nowhere, and
setting `FCM_SERVER_KEY` would not have changed that.

HTTP v1 differs in two ways that matter operationally:

* **Credentials are a service-account JSON**, not a copyable server key.
  Download it from Firebase Console → Project Settings → Service Accounts.
* **Auth is a short-lived OAuth token** derived from that file, refreshed
  automatically here, rather than a static secret in a header.

The payload shape changed too: one message per token, with `notification`
and `data` nested under `message`, and every `data` value a string — v1
rejects numbers, which is an easy way to send a push that silently 400s.
"""

from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path
from typing import Any, Dict, Optional

import httpx
from fastapi import HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.models import NotificationLog

logger = logging.getLogger(__name__)

FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"


def _v1_endpoint(project_id: str) -> str:
    return f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"


class FcmNotConfigured(RuntimeError):
    """Raised when no usable FCM credentials are present."""


class FcmCredentials:
    """Holds the service account and mints access tokens from it.

    Cached on the instance: minting is a network round trip, and doing it
    per notification would add a second of latency to every contact in an
    emergency fan-out.
    """

    def __init__(self, *, service_account_path: Optional[str], project_id: Optional[str]) -> None:
        self._path = service_account_path
        self._project_id = project_id
        self._credentials = None

    @property
    def is_configured(self) -> bool:
        return bool(self._path and Path(self._path).is_file())

    @property
    def project_id(self) -> str:
        if self._project_id:
            return self._project_id
        # The service account file names its own project, so a separate
        # setting is a convenience rather than a requirement.
        with open(self._path, encoding="utf-8") as handle:
            return json.load(handle)["project_id"]

    def _load(self):
        if self._credentials is None:
            from google.oauth2 import service_account

            self._credentials = service_account.Credentials.from_service_account_file(
                self._path, scopes=[FCM_SCOPE]
            )
        return self._credentials

    def access_token(self) -> str:
        if not self.is_configured:
            raise FcmNotConfigured(
                "FCM needs a service account JSON. Firebase Console -> Project "
                "Settings -> Service Accounts -> Generate new private key, then "
                "set FCM_SERVICE_ACCOUNT_FILE."
            )
        from google.auth.transport.requests import Request

        credentials = self._load()
        if not credentials.valid:
            credentials.refresh(Request())
        return credentials.token


def _stringify(data: Optional[Dict[str, Any]]) -> Dict[str, str]:
    """FCM v1 requires every data value to be a string.

    A raw int here produces a 400 that reads like a malformed request rather
    than a type error, so the coercion is done once, here, instead of at
    each call site.
    """
    return {str(key): "" if value is None else str(value) for key, value in (data or {}).items()}


async def send_fcm_notification(
    *,
    credentials: FcmCredentials,
    token: str,
    title: str,
    body: str,
    data: Optional[Dict[str, Any]] = None,
    session: Optional[AsyncSession] = None,
    user_id: Optional[str] = None,
    device_id: Optional[str] = None,
) -> Dict[str, Any]:
    """Sends one push. Raises [FcmNotConfigured] when credentials are absent."""
    access_token = await asyncio.to_thread(credentials.access_token)
    project_id = credentials.project_id

    payload = {
        "message": {
            "token": token,
            "notification": {"title": title, "body": body},
            "data": _stringify(data),
            "android": {"priority": "high"},
            "apns": {"headers": {"apns-priority": "10"}},
        }
    }

    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.post(
            _v1_endpoint(project_id),
            json=payload,
            headers={
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json",
            },
        )

    status = "sent" if response.status_code < 300 else "failed"

    if session is not None:
        # The token is a device identifier, so only its tail is recorded —
        # enough to correlate a failure, not enough to address a handset.
        session.add(
            NotificationLog(
                user_id=user_id,
                device_id=device_id,
                token=token[-12:] if token else None,
                channel="fcm",
                status=status,
                payload=f"title={title}",
            )
        )
        await session.commit()

    if response.status_code >= 300:
        logger.warning("FCM rejected a push: status=%s", response.status_code)
        raise HTTPException(
            status_code=response.status_code,
            detail=f"FCM send failed: {response.text[:200]}",
        )

    return response.json()
