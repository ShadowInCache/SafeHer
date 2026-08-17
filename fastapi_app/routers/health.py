from fastapi import APIRouter
from fastapi_app.deps import SettingsDep
import socket
from fastapi_app.realtime import manager
import httpx
import redis
from sqlalchemy.engine import make_url

from fastapi_app.mqtt_service import get_mqtt_status

router = APIRouter(tags=["health"])


def _redis_reachable(settings) -> bool:
    """Whether Redis answers. Reported, never used to judge health.

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
        with socket.create_connection((settings.redis_host, settings.redis_port), timeout=0.3):
            pass
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


@router.get("/health")
@router.get("/api/v1/health")
def health(settings: SettingsDep):
    """Liveness. `ok` means the API can serve requests.

    Deliberately does not touch the database: this endpoint is what the host
    polls to decide whether to keep the instance alive, and making it depend
    on a managed database that can pause under load turns a slow query into
    a restart loop.
    """
    return {
        "status": "ok",
        "service": settings.app_name,
        "environment": settings.environment,
        "hostname": socket.gethostname(),
        # Informational. Redis is not a dependency of this API, so its
        # absence is not a fault -- see `_redis_reachable`.
        "redis": "connected" if _redis_reachable(settings) else "not configured",
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
def status(settings: SettingsDep):
    processor_health = "unknown"
    try:
        with httpx.Client(timeout=2.0) as client:
            resp = client.get(f"{settings.event_processor_url}/health")
            processor_health = "healthy" if resp.status_code == 200 else "degraded"
    except Exception:
        processor_health = "unreachable"

    return {
        "status": "running",
        "environment": settings.environment,
        "api_prefix": settings.api_prefix,
        "redis": {"host": settings.redis_host, "port": settings.redis_port},
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
