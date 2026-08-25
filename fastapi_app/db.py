from datetime import datetime, timezone
import logging
from pathlib import Path
import sqlite3

from sqlalchemy.engine import make_url
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import declarative_base

from fastapi_app.config import get_settings

Base = declarative_base()
logger = logging.getLogger(__name__)

_REQUIRED_USER_COLUMNS = {
    "id",
    "email",
    "password_hash",
    "full_name",
    "phone",
    "avatar_url",
    "push_notifications",
    "sms_notifications",
    "email_notifications",
    "location_sharing",
    "role",
    "is_active",
    "created_at",
    "updated_at",
}


def sync_database_url(raw_url: str) -> str:
    """The URL with any async driver suffix stripped.

    Alembic's offline mode and psycopg-based tooling both want the plain
    dialect name, while the app engine wants the async one.
    """
    url = make_url(raw_url)
    base = url.drivername.split("+", 1)[0]
    return str(url.set(drivername=base))


def _build_async_database_url(raw_url: str) -> str:
    url = make_url(raw_url)
    drivername = url.drivername

    if drivername.startswith("postgresql") and not drivername.endswith("+asyncpg"):
        url = url.set(drivername="postgresql+asyncpg")
    elif drivername.startswith("sqlite") and not drivername.endswith("+aiosqlite"):
        url = url.set(drivername="sqlite+aiosqlite")

    if url.drivername.startswith("postgresql"):
        # Managed Postgres providers hand out libpq-style connection strings.
        # asyncpg is not libpq and rejects those spellings as unexpected
        # keyword arguments, so they are translated here rather than left to
        # fail at the first connection -- which, on a deploy, means the whole
        # API failing to start.
        query = dict(url.query)

        # `sslmode=require` (Supabase, Neon, most hosts). Dropping it silently
        # is not an option: these providers refuse unencrypted connections.
        sslmode = query.pop("sslmode", None)
        if sslmode is not None:
            if sslmode in {"disable", "allow"}:
                query.pop("ssl", None)
            else:
                query["ssl"] = "require"

        # `channel_binding=require` ships in Neon's default copy-paste string,
        # so this is the likeliest URL anyone will actually paste. asyncpg has
        # no such parameter; it negotiates SCRAM channel binding itself when
        # the server asks for it, so the guarantee is kept by dropping the
        # hint rather than by honouring it.
        query.pop("channel_binding", None)

        url = url.set(query=query)

    # Ensure SQLite file directory exists for relative paths
    if url.drivername.startswith("sqlite") and url.database and url.database != ":memory":
        db_path = Path(url.database)
        if not db_path.is_absolute():
            db_path = Path.cwd() / db_path
        db_path.parent.mkdir(parents=True, exist_ok=True)

    # `str(url)` is NOT usable here. SQLAlchemy's `URL.__str__` masks the
    # password as literal `***` -- excellent for logs, fatal for a connection
    # string. Returning it produced a URL that authenticates as the password
    # "***", so every password-protected Postgres refused the connection with
    # "password authentication failed", pointing the operator at their
    # credentials rather than at this line.
    #
    # It never showed up in development because SQLite has no password, and
    # it would have surfaced on the first production deploy.
    return url.render_as_string(hide_password=False)


def _resolve_sqlite_path(raw_url: str) -> Path | None:
    url = make_url(raw_url)
    if not url.drivername.startswith("sqlite"):
        return None
    if not url.database or url.database == ":memory:":
        return None

    db_path = Path(url.database)
    if not db_path.is_absolute():
        db_path = Path.cwd() / db_path
    return db_path


def _normalize_sqlite_url_for_path(raw_url: str, db_path: Path) -> str:
    parsed = make_url(raw_url)
    database = str(db_path).replace("\\", "/")
    if db_path.is_absolute():
        return f"sqlite:///{database}"
    return str(parsed.set(database=database))


def _resolve_compatible_database_url(raw_url: str) -> str:
    db_path = _resolve_sqlite_path(raw_url)
    if db_path is None or not db_path.exists():
        return raw_url

    try:
        with sqlite3.connect(db_path) as conn:
            row = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='users'"
            ).fetchone()
            if row is None:
                return raw_url

            user_columns = {
                column[1]
                for column in conn.execute("PRAGMA table_info(users)").fetchall()
            }
    except sqlite3.DatabaseError as exc:
        logger.warning("Skipping SQLite compatibility check for %s: %s", db_path, exc)
        return raw_url

    missing_columns = sorted(_REQUIRED_USER_COLUMNS - user_columns)
    if not missing_columns:
        return raw_url

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    backup_path = db_path.with_name(f"{db_path.stem}.legacy_{timestamp}{db_path.suffix}")
    try:
        db_path.replace(backup_path)
        logger.warning(
            "Detected legacy SQLite schema (missing users columns: %s). Backed up %s to %s and will recreate schema.",
            ", ".join(missing_columns),
            db_path,
            backup_path,
        )
        return raw_url
    except PermissionError:
        fresh_path = db_path.with_name(f"{db_path.stem}.runtime{db_path.suffix}")
        logger.warning(
            "Detected legacy SQLite schema (missing users columns: %s), but %s is locked. Switching runtime database to %s.",
            ", ".join(missing_columns),
            db_path,
            fresh_path,
        )
        return _normalize_sqlite_url_for_path(raw_url, fresh_path)


_settings = get_settings()
_effective_database_url = _resolve_compatible_database_url(_settings.database_url)
DATABASE_URL = _build_async_database_url(_effective_database_url)
_is_sqlite = DATABASE_URL.startswith("sqlite")

# `pool_pre_ping` is what stops the first request after an idle period from
# failing. The hosted deployment sleeps, and Postgres closes idle connections
# from its side; without a pre-ping SQLAlchemy hands the next request a
# connection that is already dead, the query raises, and the client gets a
# 500. The pool then discards it, so a retry succeeds -- which is why this
# looked intermittent and unreproducible. Observed directly against the
# deployed API: POST /auth/login returned 500, and the identical request a
# moment later returned a correct 401.
#
# On the mobile side that 500 surfaces as "couldn't sign in / couldn't connect
# to the server" on the first attempt after the app has been idle, which is
# the worst possible moment for a safety app to look broken.
#
# `pool_recycle` retires connections before the server is likely to, so the
# ping usually has nothing to catch. SQLite gets neither: it is a local file
# with no idle timeout, and the pool arguments do not apply to its driver.
engine = create_async_engine(
    DATABASE_URL,
    echo=_settings.debug,
    future=True,
    **({} if _is_sqlite else {"pool_pre_ping": True, "pool_recycle": 280}),
)
SessionLocal = async_sessionmaker(bind=engine, expire_on_commit=False, class_=AsyncSession)


async def get_session() -> AsyncSession:
    async with SessionLocal() as session:
        yield session


def _alembic_config() -> "Config":
    from alembic.config import Config

    cfg = Config(str(Path(__file__).resolve().parent.parent / "alembic.ini"))
    cfg.set_main_option("script_location", str(Path(__file__).resolve().parent.parent / "alembic"))
    # Escape Alembic's interpolation character; Supabase passwords may contain `%`.
    cfg.set_main_option("sqlalchemy.url", DATABASE_URL.replace("%", "%%"))
    return cfg


def _sync_schema(connection) -> None:
    """Bring the schema to head, adopting a pre-existing create_all database.

    Historically the schema was built by ``Base.metadata.create_all``, which
    leaves no ``alembic_version`` row. Such a database is already structurally
    at head but Alembic does not know it, so upgrading would replay 0001 and
    fail on tables that already exist. Stamping first records the truth, then
    the upgrade is a no-op; future migrations apply normally.
    """
    from alembic import command
    from alembic.migration import MigrationContext
    from sqlalchemy import inspect

    cfg = _alembic_config()
    cfg.attributes["connection"] = connection

    inspector = inspect(connection)
    tables = set(inspector.get_table_names())
    current = MigrationContext.configure(connection).get_current_revision()

    if current is None and "users" in tables:
        logger.warning(
            "Database has tables but no alembic_version; stamping at head to "
            "adopt the pre-migration schema."
        )
        command.stamp(cfg, "head")

    command.upgrade(cfg, "head")


async def init_db() -> None:
    """Apply migrations. Migrations are the single source of schema truth.

    ``create_all`` is deliberately not used: it silently diverges from the
    migration chain, which is how this database ended up with no
    ``alembic_version`` and six migrations that had never run.
    """
    import fastapi_app.models  # noqa: F401

    async with engine.begin() as conn:
        await conn.run_sync(_sync_schema)
