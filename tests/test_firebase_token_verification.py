"""Regression tests for Firebase ID token verification.

Two failures found against the live `safeher-2a1f2` project:

1. A freshly-minted token was rejected as "Token used too early" because the
   local clock trailed Google's by a second. That surfaces as intermittent,
   unreproducible sign-in failures rather than a clean error.
2. Phone and anonymous sign-ins carry no `email` claim, and every such account
   was given a `@phone.safeherapp.com` address regardless of provider.
"""

from __future__ import annotations

import os
import unittest
from unittest.mock import patch

os.environ.setdefault("DATABASE_URL", "sqlite:///./test_safeher.db")
os.environ.setdefault("ENABLE_MQTT_WORKER", "false")
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-key-change-me")
os.environ.setdefault("LOG_LEVEL", "WARNING")

from fastapi import HTTPException

from fastapi_app.services import firebase_auth

PROJECT = "safeher-2a1f2"


def _claims(**overrides) -> dict:
    base = {
        "iss": f"https://securetoken.google.com/{PROJECT}",
        "aud": PROJECT,
        "user_id": "uid-123",
        "sub": "uid-123",
    }
    base.update(overrides)
    return base


class TestClockSkewTolerance(unittest.TestCase):
    def test_verification_requests_a_skew_allowance(self):
        """Zero tolerance is what made valid tokens fail intermittently."""
        with patch.object(
            firebase_auth, "_verify_with_google", return_value=_claims()
        ) as verify:
            firebase_auth.verify_firebase_id_token(id_token="t", project_id=PROJECT)

        self.assertEqual(
            verify.call_args.kwargs["clock_skew_in_seconds"],
            firebase_auth.CLOCK_SKEW_TOLERANCE_SECONDS,
        )
        self.assertGreaterEqual(
            firebase_auth.CLOCK_SKEW_TOLERANCE_SECONDS,
            5,
            "a tolerance under a few seconds does not cover ordinary clock drift",
        )

    def test_rejection_reason_is_logged_but_not_returned(self):
        """The client gets a generic 401; the reason goes to the log only.

        Distinguishing "expired" from "wrong audience" helps someone probing the
        endpoint and does not help a legitimate client.
        """
        # Asserted on the logger directly rather than through `assertLogs`,
        # whose temporary handler behaves differently depending on which other
        # test modules pytest has already imported.
        with patch.object(
            firebase_auth, "_verify_with_google", side_effect=ValueError("Token used too early")
        ):
            with patch.object(firebase_auth.logger, "warning") as warn:
                with self.assertRaises(HTTPException) as ctx:
                    firebase_auth.verify_firebase_id_token(id_token="t", project_id=PROJECT)

        self.assertEqual(ctx.exception.status_code, 401)
        self.assertNotIn("too early", str(ctx.exception.detail))
        warn.assert_called_once()
        self.assertIn("too early", " ".join(str(a) for a in warn.call_args.args))


class TestSyntheticAddresses(unittest.TestCase):
    """Providers without an email claim still need a stable account key."""

    def _identity(self, claims: dict):
        with patch.object(firebase_auth, "_verify_with_google", return_value=claims):
            return firebase_auth.verify_firebase_id_token(id_token="t", project_id=PROJECT)

    def test_real_email_is_preserved(self):
        identity = self._identity(_claims(email="Asha@Example.com "))
        self.assertEqual(identity.email, "asha@example.com", "addresses are normalised")

    def test_anonymous_is_tagged_as_anonymous(self):
        identity = self._identity(
            _claims(provider_id="anonymous", firebase={"sign_in_provider": "anonymous"})
        )
        self.assertEqual(identity.email, "uid-123@anonymous.safeherapp.com")

    def test_phone_is_tagged_as_phone(self):
        identity = self._identity(_claims(firebase={"sign_in_provider": "phone"}))
        self.assertEqual(identity.email, "uid-123@phone.safeherapp.com")

    def test_unknown_provider_falls_back_without_mislabelling(self):
        identity = self._identity(_claims(firebase={"sign_in_provider": "github.com"}))
        self.assertEqual(
            identity.email,
            "uid-123@firebase.safeherapp.com",
            "an unrecognised provider must not be filed as a phone user",
        )

    def test_synthetic_address_is_stable_for_the_same_uid(self):
        """Re-signing in must resolve to the same account, not a new one."""
        claims = _claims(firebase={"sign_in_provider": "anonymous"})
        self.assertEqual(self._identity(claims).email, self._identity(claims).email)

    def test_missing_uid_is_rejected(self):
        with self.assertRaises(HTTPException) as ctx:
            self._identity({"iss": "x", "aud": PROJECT})
        self.assertEqual(ctx.exception.status_code, 401)


if __name__ == "__main__":
    unittest.main()
