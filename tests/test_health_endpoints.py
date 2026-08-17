"""What /health and /status may say — and what they must never say.

Both are unauthenticated by design: a host polls `/health` to decide whether
to keep an instance alive, and it cannot hold a token. That makes everything
they return public, which is easy to forget when adding "just one more"
diagnostic field.

`/status` returned `settings.database_url` verbatim. On the deployed instance
that published the Neon username, password and host to anyone who fetched
the URL — full read and write access to every incident, location and
emergency contact SafeHer holds. It was found by reading the handler, not by
any test, which is why these exist now.
"""

from __future__ import annotations

import os
import unittest

os.environ["DATABASE_URL"] = "sqlite:///./test_safeher.db"
os.environ["ENABLE_MQTT_WORKER"] = "false"
os.environ["JWT_SECRET_KEY"] = "test-secret-key-change-me"
os.environ["LOG_LEVEL"] = "WARNING"

import httpx

from fastapi_app.config import Settings, get_settings
from fastapi_app.main import app
from fastapi_app.routers.health import _describe_database

# A realistic managed-Postgres URL. The password is invented but shaped like
# a real one, so a substring check is a meaningful assertion.
LIVE_URL = "postgresql://neondb_owner:npg_R3al1sticSecret@ep-cool-a1b2.us-east-2.aws.neon.tech/neondb?sslmode=require"
PASSWORD = "npg_R3al1sticSecret"


class TestDatabaseIsDescribedNotDisclosed(unittest.TestCase):
    def test_the_password_never_appears(self):
        described = str(_describe_database(LIVE_URL))

        self.assertNotIn(PASSWORD, described)

    def test_the_username_never_appears(self):
        # A username is half of a credential and narrows any brute force.
        self.assertNotIn("neondb_owner", str(_describe_database(LIVE_URL)))

    def test_an_operator_still_learns_what_they_need(self):
        # The point is not to say nothing. Which engine, which host and which
        # database is what someone diagnosing a deploy actually needs, and
        # none of it is secret.
        described = _describe_database(LIVE_URL)

        self.assertEqual(described["engine"], "postgresql")
        self.assertEqual(described["database"], "neondb")
        self.assertIn("neon.tech", described["host"])

    def test_a_local_sqlite_url_is_handled(self):
        described = _describe_database("sqlite:///./safeher.db")

        self.assertEqual(described["engine"], "sqlite")
        self.assertEqual(described["host"], "local file")

    def test_an_unparseable_url_does_not_raise(self):
        # A health endpoint that 500s because it could not parse a setting is
        # worse than one that says less.
        self.assertEqual(_describe_database("not a url at all")["engine"], "unparseable")


class TestEndpoints(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://testserver"
        )

    async def asyncTearDown(self):
        await self.client.aclose()

    async def test_health_is_ok_without_redis(self):
        # Nothing in this API uses Redis. Reporting `degraded` for its absence
        # meant every healthy deployment looked unhealthy forever, and a
        # monitor that is always red is a monitor nobody reads.
        response = await self.client.get("/health")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["status"], "ok")

    async def test_health_still_reports_redis_as_information(self):
        # Removing the field would hide a genuine outage once something does
        # depend on it. It is reported, it just does not decide health.
        self.assertIn("redis", (await self.client.get("/health")).json())

    async def test_status_leaks_no_credential(self):
        # The regression that matters. Asserted against the whole response
        # body rather than one field, because the next diagnostic someone
        # adds is the one that leaks.
        strict = Settings(**{**get_settings().model_dump(), "database_url": LIVE_URL})
        app.dependency_overrides[get_settings] = lambda: strict
        try:
            body = (await self.client.get("/status")).text

            self.assertNotIn(PASSWORD, body)
            self.assertNotIn("neondb_owner", body)
        finally:
            app.dependency_overrides.pop(get_settings, None)

    async def test_status_still_names_the_engine(self):
        body = (await self.client.get("/status")).json()

        self.assertIn("database", body)
        self.assertIn("engine", body["database"])


if __name__ == "__main__":
    unittest.main()
