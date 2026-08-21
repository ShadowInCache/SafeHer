"""Shared FastAPI dependencies.

They live outside the routers so two of them cannot end up with subtly
different constructions of the same collaborator — which is exactly what
happened with the evidence store: `media.py` took it as an injectable
dependency while `shares.py` built its own, so a test that redirected
storage only redirected half the app and the shared-download path read from
the wrong directory.
"""

from typing import Annotated

from fastapi import Depends

from fastapi_app.config import Settings, get_settings
from fastapi_app.services.evidence_backends import build_backend
from fastapi_app.services.evidence_store import EvidenceStore, derive_key
from fastapi_app.services.notifications import FcmCredentials

SettingsDep = Annotated[Settings, Depends(get_settings)]


def get_evidence_store(settings: Settings = Depends(get_settings)) -> EvidenceStore:
    """The evidence store, pointed at whichever backend is configured.

    `build_backend` prefers Supabase Storage over the local directory, because
    the local one silently loses everything on a host with an ephemeral
    filesystem -- which is what production runs on.
    """
    return EvidenceStore(
        backend=build_backend(settings),
        key=derive_key(settings.jwt_secret_key, explicit_key=settings.evidence_encryption_key),
    )

def fcm_credentials(settings) -> FcmCredentials:
    """One place that knows how FCM credentials are built.

    Four call sites used to construct the legacy `server_key=` argument
    independently, so migrating meant finding all four. Centralised now.
    """
    return FcmCredentials(
        service_account_path=settings.fcm_service_account_file,
        service_account_json=settings.fcm_service_account_json,
        project_id=settings.firebase_project_id,
    )
