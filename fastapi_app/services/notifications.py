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
import base64
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

    def __init__(
        self,
        *,
        service_account_path: Optional[str] = None,
        service_account_json: Optional[str] = None,
        project_id: Optional[str] = None,
    ) -> None:
        self._path = service_account_path
        self._json = service_account_json
        self._project_id = project_id
        self._credentials = None
        self._info_cache: Optional[Dict[str, Any]] = None

    def _info(self) -> Optional[Dict[str, Any]]:
        """The service account as a dict, from whichever source exists.

        A path works on a developer machine, where the file is gitignored and
        stays out of the repository. It does not work on a host with an
        ephemeral filesystem and nothing to copy the file from -- which is
        every managed platform -- so the same credential also travels as an
        environment variable.

        The variable is accepted raw or base64-encoded. Raw is readable in a
        dashboard; base64 survives any UI that reflows or trims the private
        key's embedded newlines, which is a corruption that surfaces much
        later as an unhelpful signature error.
        """
        if self._info_cache is not None:
            return self._info_cache

        raw = (self._json or "").strip()
        if raw:
            try:
                self._info_cache = json.loads(raw)
            except ValueError:
                try:
                    self._info_cache = json.loads(base64.b64decode(raw).decode("utf-8"))
                except Exception:
                    # Deliberately says nothing about the value itself: this
                    # is a private key, and the log is the wrong place for
                    # even a fragment of it.
                    logger.error(
                        "FCM_SERVICE_ACCOUNT_JSON is set but is neither valid JSON "
                        "nor valid base64-encoded JSON; push is disabled."
                    )
                    return None
            return self._info_cache

        if self._path and Path(self._path).is_file():
            with open(self._path, encoding="utf-8") as handle:
                self._info_cache = json.load(handle)
            return self._info_cache

        return None

    @property
    def is_configured(self) -> bool:
        info = self._info()
        # A file or variable that exists but is missing the fields Google
        # needs is not configured, it is misconfigured -- and reporting it as
        # configured would turn that into a failure inside a dispatch.
        return bool(info and info.get("private_key") and info.get("client_email"))

    @property
    def status(self) -> str:
        """Why push is off, in a word an operator can act on.

        `is_configured` being False has at least four distinct causes, and a
        bare `false` sends whoever is deploying to guess between them. That
        guessing cost a real afternoon: a credential set as a *path* on a host
        that never receives the file looks identical, from outside, to one
        that was never set at all.

        Deliberately says nothing about the credential's contents -- no
        length, no prefix, no fragment. A private key is not something to
        describe in an API response, however helpfully.
        """
        if self._json and self._json.strip():
            info = self._info()
            if info is None:
                return "unreadable: the value is neither JSON nor base64-encoded JSON"
            if not (info.get("private_key") and info.get("client_email")):
                return "incomplete: parsed, but has no private_key or client_email"
            return "ready"

        if self._path:
            if not Path(self._path).is_file():
                return (
                    f"missing file: nothing at {self._path!r}. A deployed host has "
                    "no such file -- set FCM_SERVICE_ACCOUNT_JSON to its contents instead"
                )
            return "ready" if self.is_configured else "incomplete: the file has no private_key"

        return "not set: neither FCM_SERVICE_ACCOUNT_JSON nor FCM_SERVICE_ACCOUNT_FILE"

    @property
    def project_id(self) -> str:
        if self._project_id:
            return self._project_id
        # The service account names its own project, so a separate setting is
        # a convenience rather than a requirement.
        info = self._info() or {}
        return info["project_id"]

    def _load(self):
        if self._credentials is None:
            from google.oauth2 import service_account

            self._credentials = service_account.Credentials.from_service_account_info(
                self._info(), scopes=[FCM_SCOPE]
            )
        return self._credentials

    def access_token(self) -> str:
        if not self.is_configured:
            raise FcmNotConfigured(
                "FCM needs a service account. Firebase Console -> Project "
                "Settings -> Service Accounts -> Generate new private key, then "
                "either set FCM_SERVICE_ACCOUNT_FILE to the path (local "
                "development) or paste the file's contents into "
                "FCM_SERVICE_ACCOUNT_JSON (any deployed host)."
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
