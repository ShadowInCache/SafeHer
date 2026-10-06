"""Security must not depend on remembering an environment variable.

Three protections used to key off `settings.environment`, a free-text field
whose default is `"development"`:

* request rate limiting was disabled,
* CORS widened to `allow_origins=["*"]`,
* and (in `mqtt_service`) device events skipped their `auth_secret` check.

So a deployment that simply never set ENVIRONMENT served production traffic
with no limits on sign-in or password reset, open to every origin on the
internet, accepting unauthenticated device events. Nothing failed loudly — the
app ran wide open and looked healthy.

These tests pin the replacement: every switch is explicit and defaults to safe,
so forgetting one costs a throttled test suite rather than an unprotected
deployment.
"""

import unittest

from fastapi_app.config import Settings, get_settings


def _default(name: str):
    """The declared default, independent of this machine's .env."""
    return Settings.model_fields[name].default


class SecurityDefaultsTests(unittest.TestCase):
    def test_rate_limiting_is_on_unless_switched_off(self):
        self.assertFalse(
            _default("disable_rate_limiting"),
            "a deployment that forgets a variable must not lose rate limiting",
        )

    def test_device_events_require_authentication_by_default(self):
        self.assertFalse(
            _default("allow_unauthenticated_device_events"),
            "an unauthenticated MQTT publish can create an incident in a "
            "named user's account and notify their emergency contacts",
        )

    def test_the_mqtt_worker_is_off_by_default(self):
        # No current firmware publishes MQTT: the glove is BLE, the glasses
        # are HTTP. An ingest path nothing feeds is attack surface with no
        # corresponding feature.
        self.assertFalse(_default("enable_mqtt_worker"))

    def test_cors_does_not_default_to_a_wildcard(self):
        origins = _default("allow_origins")
        self.assertNotIn(
            "*",
            origins,
            "a wildcard origin plus credentials is forbidden by the CORS spec, "
            "and a wildcard without them still invites every origin to call the API",
        )

    def test_no_security_switch_reads_the_environment_string(self):
        # The property that makes all of the above hold. `environment` is for
        # describing a deployment -- choosing log levels, seeding a localhost
        # CORS regex -- and must never be what decides whether a protection
        # runs, because its default is the permissive value.
        import inspect

        from fastapi_app import main, mqtt_service

        for module in (main, mqtt_service):
            source = inspect.getsource(module)
            for marker in ("rate_limiting_enabled =", "allow_origins="):
                for line in source.splitlines():
                    stripped = line.strip()
                    if stripped.startswith("#") or marker not in stripped:
                        continue
                    self.assertNotIn(
                        "environment",
                        stripped,
                        f"{module.__name__}: {stripped!r} keys a protection on "
                        "the environment string",
                    )

    def test_the_live_settings_object_agrees(self):
        # The defaults above are what a deployment inherits; this checks the
        # loaded object exposes them rather than only declaring them.
        settings = get_settings()
        for name in (
            "disable_rate_limiting",
            "allow_unauthenticated_device_events",
            "enable_mqtt_worker",
        ):
            self.assertIsInstance(getattr(settings, name), bool, name)


if __name__ == "__main__":
    unittest.main()
