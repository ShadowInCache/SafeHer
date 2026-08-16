"""Prove the app can reach the database engine production actually uses.

Most test modules pin `DATABASE_URL` to SQLite at import time, deliberately:
the suite must be hermetic and fast. The cost is that nothing in it ever
touches Postgres, and the two databases disagree in ways that only surface
on a deploy -- migration 0007 shipped `is_verified = 1`, which SQLite
accepts and Postgres rejects outright.

This runs in CI against a real Postgres service. It is a boot check, not a
test suite: it asserts the connection string survives translation, the
engine connects, and the schema the migrations just built is actually there.
"""

from __future__ import annotations

import asyncio
import os
import sys
from pathlib import Path

# Run as a script from anywhere, including `python scripts/...` in CI, where
# the repo root is not on sys.path.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

os.environ.setdefault("ENABLE_MQTT_WORKER", "false")
os.environ.setdefault("LOG_LEVEL", "WARNING")

from sqlalchemy import text
from sqlalchemy.engine import make_url

from fastapi_app.db import DATABASE_URL, engine

EXPECTED_TABLES = {"users", "incidents", "emergency_contacts", "locations", "media"}


async def main() -> int:
    url = make_url(DATABASE_URL)

    if not url.drivername.startswith("postgresql"):
        print(f"FAIL: expected Postgres, got {url.drivername}")
        return 1

    # The bug this catches: `str(url)` masks the password as literal `***`,
    # which produced a connection string that authenticated as "***".
    if url.password == "***":
        print("FAIL: password was masked in the connection string")
        return 1

    # libpq spellings asyncpg rejects as unexpected keyword arguments.
    leftovers = set(url.query) - {"ssl", "server_settings", "command_timeout"}
    if leftovers:
        print(f"FAIL: asyncpg would reject these query parameters: {leftovers}")
        return 1

    async with engine.connect() as connection:
        version = (await connection.execute(text("select version()"))).scalar()
        rows = await connection.execute(
            text("select tablename from pg_tables where schemaname = 'public'")
        )
        tables = {row[0] for row in rows}

    print(f"connected: {version.split(',')[0]}")

    missing = EXPECTED_TABLES - tables
    if missing:
        print(f"FAIL: migrations did not create: {sorted(missing)}")
        return 1

    print(f"schema present: {len(tables)} tables, including all expected")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
