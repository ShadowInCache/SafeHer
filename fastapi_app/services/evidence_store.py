"""Encrypted-at-rest storage for emergency evidence (SRS FR-EMG-07).

Evidence here is audio or video of an assault in progress. Two properties
matter more than convenience:

* **It is never readable from disk.** Every file is sealed with AES-256-GCM
  before it touches the filesystem, so a stolen backup, a misconfigured
  volume mount or a shared dev machine yields ciphertext.
* **It is never reachable by URL alone.** Nothing is served from a public
  bucket or a guessable CDN path — retrieval goes through an authenticated,
  ownership-checked endpoint. A link that leaks is not enough to view it.

Cloudinary remains wired up in `routers/media.py` for projects that have an
account, but it is not the default: storing evidence on infrastructure the
project already runs needs no third-party signup, and keeps the recording
inside the same trust boundary as the incident it belongs to.
"""

from __future__ import annotations

import hashlib
import hmac
import logging
import os
from pathlib import Path
from typing import Optional
from uuid import uuid4

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

logger = logging.getLogger(__name__)

# AES-GCM standard nonce length. Stored as a prefix on the ciphertext, which
# is safe: a nonce is not secret, only single-use.
NONCE_BYTES = 12

_KEY_INFO = b"safeher-evidence-encryption-v1"


class EvidenceStoreError(RuntimeError):
    """Raised when evidence cannot be written or read back."""


def derive_key(secret: str, *, explicit_key: Optional[str] = None) -> bytes:
    """Returns the 32-byte AES key.

    A dedicated `EVIDENCE_ENCRYPTION_KEY` wins when set. Otherwise the key is
    derived from the JWT secret with HKDF-style expansion.

    Deriving rather than falling back to plaintext is deliberate: a
    "encryption is optional if unconfigured" path would mean the one
    deployment nobody configured is the one storing assault recordings in the
    clear. Derivation guarantees there is always a key, and the separate
    `info` string keeps it unrelated to the token-signing key even though it
    shares a root.
    """
    if explicit_key:
        # Accept either raw text or hex; hash either way so length is fixed.
        return hashlib.sha256(explicit_key.encode("utf-8")).digest()
    return hmac.new(secret.encode("utf-8"), _KEY_INFO, hashlib.sha256).digest()


class EvidenceStore:
    def __init__(self, *, directory: str, key: bytes) -> None:
        if len(key) != 32:
            raise EvidenceStoreError("Evidence encryption key must be 32 bytes (AES-256).")
        self._directory = Path(directory)
        self._key = key

    def _path_for(self, storage_id: str) -> Path:
        # Basename only: the id is generated here, but treating it as
        # untrusted costs nothing and keeps a future caller from walking out
        # of the directory with one.
        return self._directory / f"{Path(storage_id).name}.enc"

    def write(self, data: bytes) -> str:
        """Seals [data] and returns the storage id needed to read it back."""
        if not data:
            raise EvidenceStoreError("Refusing to store an empty recording.")

        storage_id = uuid4().hex
        nonce = os.urandom(NONCE_BYTES)
        sealed = AESGCM(self._key).encrypt(nonce, data, None)

        try:
            self._directory.mkdir(parents=True, exist_ok=True)
            path = self._path_for(storage_id)
            # Written to a temporary name and moved into place, so a crash
            # mid-write cannot leave a truncated file that later fails to
            # decrypt with no way to tell why.
            temporary = path.with_suffix(".part")
            temporary.write_bytes(nonce + sealed)
            temporary.replace(path)
        except OSError as exc:
            raise EvidenceStoreError(f"Could not store evidence: {exc}") from exc

        return storage_id

    def read(self, storage_id: str) -> bytes:
        path = self._path_for(storage_id)
        try:
            blob = path.read_bytes()
        except OSError as exc:
            raise EvidenceStoreError(f"Could not read evidence: {exc}") from exc

        if len(blob) <= NONCE_BYTES:
            raise EvidenceStoreError("Stored evidence is truncated.")

        nonce, sealed = blob[:NONCE_BYTES], blob[NONCE_BYTES:]
        try:
            return AESGCM(self._key).decrypt(nonce, sealed, None)
        except Exception as exc:  # InvalidTag and friends
            # Authentication failure means the file was altered or the key
            # changed. Either way the bytes are not trustworthy evidence, so
            # they are refused rather than returned as-is.
            raise EvidenceStoreError(
                "Evidence failed its integrity check and was not returned."
            ) from exc

    def delete(self, storage_id: str) -> None:
        try:
            self._path_for(storage_id).unlink(missing_ok=True)
        except OSError as exc:
            logger.warning("Could not delete evidence %s: %s", storage_id, exc)
