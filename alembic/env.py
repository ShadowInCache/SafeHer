"""Alembic environment.

The application engine is async (``+aiosqlite`` / ``+asyncpg``), so migrations
must be driven through an async engine too. Configuring a sync
``engine_from_config`` with an async URL raises ``MissingGreenlet`` at connect
time, which is why migrations previously could not run at all.
"""

import asyncio
from logging.config import fileConfig
from pathlib import Path
import sys

from alembic import context
from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.append(str(PROJECT_ROOT))

from fastapi_app.db import Base, _build_async_database_url, sync_database_url  # noqa: E402
from fastapi_app import models  # noqa: E402,F401
from fastapi_app.config import get_settings  # noqa: E402

settings = get_settings()

# `%` is Alembic's interpolation escape; passwords in Supabase URLs can contain it.
config.set_main_option(
    "sqlalchemy.url",
    _build_async_database_url(settings.database_url).replace("%", "%%"),
)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """Emit SQL to stdout without a DBAPI connection.

    Offline mode never opens a socket, so it uses the plain sync URL to keep
    the generated script free of driver-specific prefixes.
    """
    context.configure(
        url=sync_database_url(settings.database_url),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def _run_migrations(connection: Connection) -> None:
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        # SQLite cannot ALTER most things in place; batch mode rewrites the
        # table instead, which keeps one migration set valid on both backends.
        render_as_batch=connection.dialect.name == "sqlite",
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    async with connectable.connect() as connection:
        await connection.run_sync(_run_migrations)
    await connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    # `init_db` runs migrations inside the app's own connection via
    # `run_sync`, and passes that (already sync) connection through
    # `config.attributes`. Reuse it rather than opening a second one, which on
    # SQLite would deadlock against the first connection's write lock.
    existing = config.attributes.get("connection")
    if existing is not None:
        _run_migrations(existing)
    else:
        asyncio.run(run_migrations_online())
