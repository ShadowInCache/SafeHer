"""Test-wide isolation from the developer's local configuration.

`Settings` reads the repo-root `.env`, so the moment a real SMTP host, Twilio
account or OneSignal key is configured for local development, the test suite
picks it up. That is not a cosmetic leak:

* Registration emails a verification code. With SMTP configured, running the
  suite sent real mail to made-up `@safeherapp.com` addresses on every test
  that created a user.
* `require_email_verification` follows deliverability, so configuring SMTP
  silently flipped it on and every `login` in the suite started returning
  403 — tests failing for a reason that had nothing to do with the code.

Environment variables take precedence over `.env`, so blanking them here
pins the suite to a known, offline configuration regardless of what the
developer has set up. Individual modules can still override any of these
after import if they are specifically testing the configured path.

This file must stay free of imports from `fastapi_app`: it works precisely
because it runs before any test module imports the app and constructs
`Settings`.
"""

import os

# --- outbound channels: off, so no test can reach a real person ----------
os.environ.setdefault("SMTP_HOST", "")
os.environ.setdefault("SMTP_USERNAME", "")
os.environ.setdefault("SMTP_PASSWORD", "")
os.environ.setdefault("SMTP_FROM_EMAIL", "")
os.environ.setdefault("TWILIO_ACCOUNT_SID", "")
os.environ.setdefault("TWILIO_AUTH_TOKEN", "")
os.environ.setdefault("TWILIO_FROM_NUMBER", "")
os.environ.setdefault("ONESIGNAL_APP_ID", "")
os.environ.setdefault("ONESIGNAL_API_KEY", "")
# Brevo delivers over HTTPS, so unlike SMTP it is reachable from the test
# runner on any host. Blanked for the same reason as the rest: a suite that
# can send real mail will eventually send some.
os.environ.setdefault("BREVO_API_KEY", "")
os.environ.setdefault("FCM_SERVER_KEY", "")
os.environ.setdefault("FCM_SERVICE_ACCOUNT_FILE", "")
os.environ.setdefault("FCM_SERVICE_ACCOUNT_JSON", "")
# Added after a summary test reached the live Gemini API and came back with
# a real 503 from Google. Every new outbound credential has to be listed
# here or the suite starts spending someone's quota.
os.environ.setdefault("GEMINI_API_KEY", "")

# Blanking SMTP would switch this off by itself, but stating it means a test
# never depends on that inference holding.
os.environ.setdefault("REQUIRE_EMAIL_VERIFICATION", "false")

# --- local-only infrastructure -------------------------------------------
os.environ.setdefault("DATABASE_URL", "sqlite:///./test_safeher.db")
os.environ.setdefault("ENABLE_MQTT_WORKER", "false")
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-key-change-me")
os.environ.setdefault("LOG_LEVEL", "WARNING")
