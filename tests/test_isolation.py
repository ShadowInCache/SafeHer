"""Asserts the suite cannot reach the outside world.

`Settings` reads the repo-root `.env`, so every credential a developer
configures for local work is inherited by the tests unless `conftest.py`
blanks it. That has now bitten twice: once when the suite started emailing
real verification codes to made-up addresses, and again when a summary test
reached the live Gemini API and came back with a genuine 503 from Google.

Both times the fix was one line in conftest, and both times the leak was
found by accident. This test finds it on purpose: a new outbound credential
added to `Settings` fails here until it is also neutralised, which is the
only way the rule survives being forgotten.
"""

from __future__ import annotations

import os
import unittest

os.environ["DATABASE_URL"] = "sqlite:///./test_safeher.db"
os.environ["ENABLE_MQTT_WORKER"] = "false"
os.environ["JWT_SECRET_KEY"] = "test-secret-key-change-me"
os.environ["LOG_LEVEL"] = "WARNING"

from fastapi_app.config import Settings

# Anything whose name says it addresses, authenticates to, or pays for a
# third party. Local infrastructure (the database, the JWT secret) is
# deliberately not in scope.
_OUTBOUND_HINTS = (
    "api_key",
    "auth_token",
    "server_key",
    "account_sid",
    "smtp_",
    "from_number",
    # Brevo sends email over HTTPS, so it is reachable from the test runner
    # even where SMTP ports are blocked — which makes it exactly the kind of
    # credential this guard exists for.
    "brevo",
)

# Settings that merely name a service without being able to reach it.
_ALLOWED = {
    "smtp_port",
    "smtp_use_tls",
    "smtp_use_ssl_override",
    "smtp_from_name",
    # A socket timeout, not an address or a credential — it cannot reach
    # anything by itself, and it has a non-zero default so it always reads as
    # "set".
    "smtp_timeout_seconds",
}


class TestOutboundIsolation(unittest.TestCase):
    def test_no_outbound_credential_is_configured_during_tests(self):
        settings = Settings()

        configured = {
            name: "set"
            for name in settings.model_fields
            if name not in _ALLOWED
            and any(hint in name for hint in _OUTBOUND_HINTS)
            and getattr(settings, name)
        }

        self.assertEqual(
            configured,
            {},
            "these credentials are live during the test run — add them to "
            "tests/conftest.py so the suite cannot reach a real service",
        )

    def test_the_scan_actually_looks_at_something(self):
        # Guards the guard: a hint list that matched nothing would make the
        # test above pass forever while checking nothing at all.
        settings = Settings()
        in_scope = [
            name
            for name in settings.model_fields
            if name not in _ALLOWED and any(hint in name for hint in _OUTBOUND_HINTS)
        ]

        self.assertGreaterEqual(len(in_scope), 6, f"only found {in_scope}")

    def test_email_verification_is_off(self):
        # It follows deliverability, so configuring SMTP silently switches
        # it on and every login in the suite starts returning 403.
        self.assertFalse(Settings().require_email_verification)


if __name__ == "__main__":
    unittest.main()
