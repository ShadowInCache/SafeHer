from fastapi import APIRouter
from fastapi_app.deps import SettingsDep
import socket
from fastapi_app.realtime import manager
import httpx
import redis

from fastapi_app.mqtt_service import get_mqtt_status

router = APIRouter(tags=["health"])


@router.get("/health")
@router.get("/api/v1/health")
def health(settings: SettingsDep):
    redis_ok = False
    try:
        client = redis.Redis(
            host=settings.redis_host,
            port=settings.redis_port,
            password=settings.redis_password,
            socket_connect_timeout=1,
        )
        redis_ok = bool(client.ping())
    except Exception:
        redis_ok = False

    return {
        "status": "ok" if redis_ok else "degraded",
        "service": settings.app_name,
        "environment": settings.environment,
        "hostname": socket.gethostname(),
        "redis": "connected" if redis_ok else "disconnected",
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
        "database": settings.database_url,
    }
