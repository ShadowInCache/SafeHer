import asyncio
import time

from fastapi import APIRouter
from fastapi_app.deps import SettingsDep
import socket
from fastapi_app.realtime import manager
import httpx
import redis
from sqlalchemy.engine import make_url

from fastapi_app.mqtt_service import get_mqtt_status

router = APIRouter(tags=["health"])


# Redis reachability is cached rather than probed per request.
#
# `/health` used to run the blocking probe below on every call. Measured on a
# host with no Redis listening, that cost ~647ms per request -- the configured
# 300ms timeout applied *per resolved address*, and "localhost" resolves to
# both ::1 and 127.0.0.1, so each request paid it twice. `/health` is also the
# endpoint the platform polls to decide whether to keep the instance alive, so
# a slow answer risks the restart loop this module was written to avoid; it
# just arrived through Redis instead of the database.
#
# So: liveness never probes. It reports the last known answer and, when that
# answer is stale, schedules a refresh that runs off the event loop and lands
# in time for the next caller. `/status`, which exists to be thorough rather
# than fast, waits for a fresh result.
_REDIS_TTL_SECONDS = 30.0
_redis_state: dict = {"reachable": None, "checked_at": 0.0}
_redis_refresh_task: asyncio.Task | None = None


def _probe_redis(settings) -> bool:
    """Blocking. Never call this from the event loop -- use `_refresh_redis`.

    Nothing in `fastapi_app` reads or writes Redis -- it appears only in
    config defaults and here. Letting it decide `status` meant every healthy
    deployment reported `degraded` forever, which trains everyone watching to
    ignore the field. A monitor that is always red is a monitor that is off.
    """
    try:
        # A raw precheck first: redis-py's own connect/socket timeouts don't
        # reliably bound how long client.ping() takes when nothing is
        # listening (observed 15s+ stalls in local dev on Windows, where
        # "localhost" resolves to both ::1 and 127.0.0.1 and each candidate
        # gets its own retry). A bare socket connect with an explicit short
        # timeout fails fast and skips the redis client entirely when there's
        # nothing there.
        # One address, not every address the name resolves to: create_connection
        # applies its timeout per candidate, which is how a 300ms budget became
        # 647ms on a dual-stack "localhost".
        family, socktype, proto, _canon, sockaddr = socket.getaddrinfo(
            settings.redis_host, settings.redis_port, type=socket.SOCK_STREAM
        )[0]
        probe = socket.socket(family, socktype, proto)
        probe.settimeout(0.3)
        try:
            probe.connect(sockaddr)
        finally:
            probe.close()
        client = redis.Redis(
            host=settings.redis_host,
            port=settings.redis_port,
            password=settings.redis_password,
            socket_connect_timeout=1,
            socket_timeout=1,
        )
        return bool(client.ping())
    except Exception:
        return False


def _redis_is_stale() -> bool:
    return time.monotonic() - _redis_state["checked_at"] > _REDIS_TTL_SECONDS


async def _refresh_redis(settings) -> bool:
    """Run the blocking probe in a worker thread and cache the answer."""
    reachable = await asyncio.to_thread(_probe_redis, settings)
    _redis_state["reachable"] = reachable
    _redis_state["checked_at"] = time.monotonic()
    return reachable


def _schedule_redis_refresh(settings) -> None:
    """Kick off a refresh without waiting for it.

    One at a time: a burst of health checks against an unreachable Redis
    would otherwise start a probe per request, which is the pile-up this
    change exists to prevent.
    """
    global _redis_refresh_task
    if _redis_refresh_task is not None and not _redis_refresh_task.done():
        return
    try:
        _redis_refresh_task = asyncio.create_task(_refresh_redis(settings))
    except RuntimeError:
        # No running loop (sync test client, shutdown). Nothing to refresh.
        _redis_refresh_task = None


def _redis_label() -> str:
    reachable = _redis_state["reachable"]
    if reachable is None:
        return "not checked yet"
    return "connected" if reachable else "not configured"


@router.get("/health")
@router.get("/api/v1/health")
async def health(settings: SettingsDep):
    """Liveness. `ok` means the API can serve requests.

    Constant time by construction: no database, and no network. This endpoint
    is what the host polls to decide whether to keep the instance alive, so
    anything that can be slow or unreachable must not sit inside it -- a slow
    query or a dead Redis turns into a restart loop either way.
    """
    if _redis_is_stale():
        _schedule_redis_refresh(settings)
    return {
        "status": "ok",
        "service": settings.app_name,
        "environment": settings.environment,
        "hostname": socket.gethostname(),
        # Informational, and read from cache. Redis is not a dependency of
        # this API, so its absence is not a fault -- see `_probe_redis`.
        "redis": _redis_label(),
    }


def _describe_database(url: str) -> dict:
    """The database, named but not disclosed.

    This endpoint used to return `settings.database_url` verbatim. On a
    deployed instance that is an unauthenticated URL publishing the database
    username, password and host to anyone who fetches it -- full read and
    write access to every incident, location and emergency contact SafeHer
    holds.

    What an operator actually needs from here is which engine and which host,
    neither of which is a secret.
    """
    try:
        parsed = make_url(url)
    except Exception:
        return {"engine": "unparseable"}
    return {
        "engine": parsed.drivername,
        "host": parsed.host or "local file",
        "database": parsed.database,
    }


@router.get("/status")
@router.get("/api/v1/status")
async def status(settings: SettingsDep):
    """The deep check. Allowed to be slow, unlike `/health`.

    Async and awaited rather than sync-and-blocking: as a `def` this occupied
    a threadpool worker for up to the full 2s timeout, so a handful of status
    calls against an unreachable processor could starve every other
    threadpool-bound handler.
    """
    processor_health = "unknown"
    try:
        async with httpx.AsyncClient(timeout=2.0) as client:
            resp = await client.get(f"{settings.event_processor_url}/health")
            processor_health = "healthy" if resp.status_code == 200 else "degraded"
    except Exception:
        processor_health = "unreachable"

    # Thorough on purpose: this is the endpoint to point a real readiness
    # monitor at, so it pays for a current answer rather than a cached one.
    if _redis_is_stale():
        await _refresh_redis(settings)

    return {
        "status": "running",
        "environment": settings.environment,
        "api_prefix": settings.api_prefix,
        "redis": {
            "host": settings.redis_host,
            "port": settings.redis_port,
            "reachable": _redis_state["reachable"],
        },
        "mqtt": {
            "host": settings.mqtt_host,
            "port": settings.mqtt_port,
            **get_mqtt_status(),
        },
        "websocket": manager.get_status(),
        "event_processor": {
            "url": settings.event_processor_url,
            "health": processor_health,
        },
        "database": _describe_database(settings.database_url),
    }
