"""Where sealed evidence rests, and what the storage provider can see.

The defect this covers had no symptom until it was too late to matter.
`evidence_storage_dir` defaults to `./evidence_store` — a directory on the
application server — and Render's filesystem is ephemeral. Uploads returned
201, the `media` row persisted in Postgres, and the bytes were deleted by the
next deploy. A feature whose whole purpose is producing something that still
exists in front of a court was quietly producing nothing.

Two properties are pinned here. That a configured object store is actually
preferred over the local directory that loses data, and — the one that makes
putting recordings of people in danger on someone else's infrastructure
defensible at all — that the provider never receives plaintext.
"""

from __future__ import annotations

import os
import unittest
from unittest import mock

os.environ.setdefault("DATABASE_URL", "sqlite:///./test_safeher.db")
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-key-change-me")

import httpx

from fastapi_app.config import Settings
from fastapi_app.services.evidence_backends import (
    EvidenceBackendError,
    LocalBlobBackend,
    SupabaseBlobBackend,
    build_backend,
)
from fastapi_app.services.evidence_store import EvidenceStore, EvidenceStoreError, derive_key

KEY = derive_key("unit-test-secret")
RECORDING = b"\x00\x01audio-of-an-assault\xff" * 64


class _RecordingBackend:
    """Captures exactly what a backend is handed."""

    def __init__(self):
        self.blobs: dict[str, bytes] = {}

    def put(self, key, blob):
        self.blobs[key] = blob

    def get(self, key):
        return self.blobs[key]

    def remove(self, key):
        self.blobs.pop(key, None)

    @property
    def describe(self):
        return "recording"


class TestBackendSelection(unittest.TestCase):
    def _settings(self, **overrides) -> Settings:
        base = {
            "jwt_secret_key": "x" * 40,
            "evidence_storage_dir": "./evidence_store",
        }
        base.update(overrides)
        return Settings(**base)

    def test_local_disk_is_used_when_nothing_else_is_configured(self):
        backend = build_backend(self._settings())

        self.assertIsInstance(backend, LocalBlobBackend)

    def test_supabase_wins_over_the_local_directory(self):
        """The local default is the one that loses data on an ephemeral host,
        so a configured object store must always beat it."""
        backend = build_backend(
            self._settings(
                supabase_url="https://project.supabase.co",
                supabase_secret_key="service-role-key",
            )
        )

        self.assertIsInstance(backend, SupabaseBlobBackend)
        self.assertEqual(backend.describe, "supabase:Evidence")

    def test_a_url_without_a_key_does_not_count_as_configured(self):
        """Half-configured must fall back rather than fail every upload. A
        deployment that sets the URL and forgets the key would otherwise lose
        evidence on a 401 instead of writing it somewhere."""
        backend = build_backend(self._settings(supabase_url="https://project.supabase.co"))

        self.assertIsInstance(backend, LocalBlobBackend)

    def test_the_backend_name_never_leaks_the_credential(self):
        backend = build_backend(
            self._settings(
                supabase_url="https://project.supabase.co",
                supabase_secret_key="super-secret-service-role-key",
            )
        )

        self.assertNotIn("super-secret", backend.describe)


class TestProviderNeverSeesPlaintext(unittest.TestCase):
    """The property that makes third-party evidence storage defensible."""

    def test_the_backend_is_handed_ciphertext_only(self):
        backend = _RecordingBackend()
        store = EvidenceStore(key=KEY, backend=backend)

        storage_id = store.write(RECORDING)

        stored = backend.blobs[storage_id]
        self.assertNotIn(RECORDING, stored)
        self.assertNotIn(b"audio-of-an-assault", stored)
        # Sealed, and longer than the input by nonce + GCM tag.
        self.assertGreater(len(stored), len(RECORDING))

    def test_it_round_trips_through_an_opaque_backend(self):
        backend = _RecordingBackend()
        store = EvidenceStore(key=KEY, backend=backend)

        storage_id = store.write(RECORDING)

        self.assertEqual(store.read(storage_id), RECORDING)

    def test_tampered_ciphertext_is_refused_not_returned(self):
        """A provider that alters bytes -- or a wrong key -- must produce a
        refusal, never plausible-looking evidence."""
        backend = _RecordingBackend()
        store = EvidenceStore(key=KEY, backend=backend)
        storage_id = store.write(RECORDING)

        blob = bytearray(backend.blobs[storage_id])
        blob[-1] ^= 0xFF
        backend.blobs[storage_id] = bytes(blob)

        with self.assertRaises(EvidenceStoreError):
            store.read(storage_id)


class TestSupabaseBackend(unittest.TestCase):
    def _backend(self) -> SupabaseBlobBackend:
        return SupabaseBlobBackend(
            url="https://project.supabase.co/",
            service_key="service-role-key",
            bucket="evidence",
        )

    def test_upload_targets_the_bucket_and_authenticates(self):
        captured = {}

        def fake_post(url, content=None, headers=None, timeout=None):
            captured["url"] = url
            captured["headers"] = headers
            captured["content"] = content
            return httpx.Response(200, text="{}")

        with mock.patch("httpx.post", side_effect=fake_post):
            self._backend().put("abc123", b"sealed-bytes")

        self.assertEqual(
            captured["url"],
            "https://project.supabase.co/storage/v1/object/evidence/abc123.enc",
        )
        self.assertEqual(captured["headers"]["Authorization"], "Bearer service-role-key")
        self.assertEqual(captured["content"], b"sealed-bytes")

    def test_upload_refuses_to_overwrite(self):
        """Storage ids are fresh UUIDs, so a collision means something is
        wrong -- and clobbering would destroy an earlier recording."""
        captured = {}

        def fake_post(url, content=None, headers=None, timeout=None):
            captured.update(headers)
            return httpx.Response(200, text="{}")

        with mock.patch("httpx.post", side_effect=fake_post):
            self._backend().put("abc123", b"sealed")

        self.assertEqual(captured["x-upsert"], "false")

    def test_a_refused_upload_raises_rather_than_silently_losing_it(self):
        with mock.patch("httpx.post", return_value=httpx.Response(403, text="denied")):
            with self.assertRaises(EvidenceBackendError):
                self._backend().put("abc123", b"sealed")

    def test_an_unreachable_provider_raises(self):
        with mock.patch("httpx.post", side_effect=httpx.ConnectError("no route")):
            with self.assertRaises(EvidenceBackendError):
                self._backend().put("abc123", b"sealed")

    def test_a_missing_object_raises_rather_than_returning_empty(self):
        """Returning b"" would decrypt-fail confusingly; a 404 has to say so."""
        with mock.patch("httpx.get", return_value=httpx.Response(404, text="not found")):
            with self.assertRaises(EvidenceBackendError):
                self._backend().get("abc123")

    def test_delete_never_raises(self):
        """Deletion is usually part of erasing an account. A storage hiccup
        must not block that."""
        with mock.patch("httpx.request", side_effect=httpx.ConnectError("no route")):
            self._backend().remove("abc123")  # must not raise

    def test_a_404_on_delete_is_not_worth_warning_about(self):
        with mock.patch("httpx.request", return_value=httpx.Response(404)):
            self._backend().remove("abc123")


if __name__ == "__main__":
    unittest.main()
