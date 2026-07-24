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
    "role",
    "is_active",
    "created_at",
    "updated_at",
}


def _build_async_database_url(raw_url: str) -> str:
    url = make_url(raw_url)
    drivername = url.drivername

    if drivername.startswith("postgresql") and not drivername.endswith("+asyncpg"):
        url = url.set(drivername="postgresql+asyncpg")
    elif drivername.startswith("sqlite") and not drivername.endswith("+aiosqlite"):
        url = url.set(drivername="sqlite+aiosqlite")

    # Ensure SQLite file directory exists for relative paths
    if url.drivername.startswith("sqlite") and url.database and url.database != ":memory":
        db_path = Path(url.database)
        if not db_path.is_absolute():
            db_path = Path.cwd() / db_path
        db_path.parent.mkdir(parents=True, exist_ok=True)

    return str(url)


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
engine = create_async_engine(DATABASE_URL, echo=_settings.debug, future=True)
SessionLocal = async_sessionmaker(bind=engine, expire_on_commit=False, class_=AsyncSession)


async def get_session() -> AsyncSession:
    async with SessionLocal() as session:
        yield session


async def init_db() -> None:
    # Import models here to ensure metadata is populated before create_all
    import fastapi_app.models  # noqa: F401

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
