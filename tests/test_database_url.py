"""Translating managed-Postgres connection strings for asyncpg.

Every provider hands out a libpq-style URL, because that is what `psql` and
almost every other client expects. asyncpg is not libpq: it rejects those
spellings as unexpected keyword arguments, and it does so at the first
connection attempt — which on a deploy means the API failing to start, with
a `TypeError` that names a parameter the operator did not knowingly set.

These tests exist because that failure is invisible until the moment it is
expensive, and because the exact query parameters differ per provider. Each
case below is a real connection string shape, not an invented one.
"""

from __future__ import annotations

import os
import unittest

os.environ["DATABASE_URL"] = "sqlite:///./test_safeher.db"
os.environ["ENABLE_MQTT_WORKER"] = "false"
os.environ["JWT_SECRET_KEY"] = "test-secret-key-change-me"
os.environ["LOG_LEVEL"] = "WARNING"

from sqlalchemy.engine import make_url

from fastapi_app.db import _build_async_database_url

# Parameters asyncpg's `connect()` genuinely accepts. Anything else left in
# the query string reaches it as a keyword argument and raises.
_ASYNCPG_SAFE = {"ssl", "server_settings", "command_timeout", "statement_cache_size"}


def _query_of(raw_url: str) -> dict:
    return dict(make_url(_build_async_database_url(raw_url)).query)


class TestDriverSelection(unittest.TestCase):
    def test_postgres_is_upgraded_to_asyncpg(self):
        url = _build_async_database_url("postgresql://u:p@host/db")

        self.assertTrue(url.startswith("postgresql+asyncpg://"))

    def test_an_explicit_driver_is_left_alone(self):
        url = _build_async_database_url("postgresql+asyncpg://u:p@host/db")

        self.assertTrue(url.startswith("postgresql+asyncpg://"))
        self.assertNotIn("asyncpg+asyncpg", url)

    def test_sqlite_is_upgraded_to_aiosqlite(self):
        self.assertTrue(_build_async_database_url("sqlite:///./x.db").startswith("sqlite+aiosqlite:"))


class TestNeon(unittest.TestCase):
    """Neon's dashboard copy-paste, which is what anyone will actually use."""

    DEFAULT = (
        "postgresql://neondb_owner:npg_secret@ep-cool-name-a1b2c3d4"
        ".us-east-2.aws.neon.tech/neondb?sslmode=require&channel_binding=require"
    )

    def test_channel_binding_is_removed(self):
        # asyncpg has no such parameter. It negotiates SCRAM channel binding
        # itself when the server asks, so the guarantee survives dropping the
        # hint — but leaving the hint in place is a TypeError at connect time.
        self.assertNotIn("channel_binding", _query_of(self.DEFAULT))

    def test_encryption_is_preserved_not_dropped(self):
        # The dangerous fix would be to strip every unknown parameter and
        # silently connect in the clear. Neon refuses unencrypted
        # connections, but a provider that did not would leave this quietly
        # plaintext.
        self.assertEqual(_query_of(self.DEFAULT).get("ssl"), "require")

    def test_nothing_asyncpg_rejects_survives(self):
        leftovers = set(_query_of(self.DEFAULT)) - _ASYNCPG_SAFE

        self.assertEqual(leftovers, set(), f"asyncpg would reject: {leftovers}")

    def test_the_host_and_database_are_untouched(self):
        url = make_url(_build_async_database_url(self.DEFAULT))

        self.assertEqual(url.host, "ep-cool-name-a1b2c3d4.us-east-2.aws.neon.tech")
        self.assertEqual(url.database, "neondb")
        self.assertEqual(url.username, "neondb_owner")


class TestSupabase(unittest.TestCase):
    URL = "postgresql://postgres:pw@db.abcdef.supabase.co:5432/postgres?sslmode=require"

    def test_sslmode_becomes_ssl(self):
        query = _query_of(self.URL)

        self.assertNotIn("sslmode", query)
        self.assertEqual(query.get("ssl"), "require")

    def test_the_port_survives(self):
        self.assertEqual(make_url(_build_async_database_url(self.URL)).port, 5432)


class TestSslModes(unittest.TestCase):
    def test_disable_means_no_ssl_argument_at_all(self):
        # `ssl=require` alongside `sslmode=disable` would be a contradiction
        # asyncpg resolves in the direction the operator did not ask for.
        query = _query_of("postgresql://u:p@host/db?sslmode=disable")

        self.assertNotIn("ssl", query)
        self.assertNotIn("sslmode", query)

    def test_stricter_modes_all_map_to_require(self):
        # asyncpg has no `verify-full`; `require` is the strongest thing it
        # takes here, and downgrading is better than a TypeError only because
        # the connection stays encrypted either way.
        for mode in ("require", "verify-ca", "verify-full", "prefer"):
            with self.subTest(mode=mode):
                query = _query_of(f"postgresql://u:p@host/db?sslmode={mode}")
                self.assertEqual(query.get("ssl"), "require")

    def test_a_url_with_no_query_is_unharmed(self):
        # Local Postgres in Docker, the common development case.
        self.assertEqual(_query_of("postgresql://u:p@localhost:5432/safeher"), {})


class TestPasswordsWithSpecialCharacters(unittest.TestCase):
    def test_a_percent_in_the_password_survives(self):
        # Alembic treats `%` as its interpolation character, which is why
        # db.py and alembic/env.py both escape it. Generated passwords from
        # Neon and Supabase contain it often enough to matter.
        url = make_url(_build_async_database_url("postgresql://u:pa%%25ss@host/db"))

        self.assertIsNotNone(url.password)


if __name__ == "__main__":
    unittest.main()
