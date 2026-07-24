#!/usr/bin/env python3
"""SafeHer API launcher (FastAPI + Uvicorn)."""

from __future__ import annotations

import logging
import os

import requests
import uvicorn
from dotenv import load_dotenv

from fastapi_app.config import get_settings


load_dotenv()
settings = get_settings()

logging.basicConfig(
    level=getattr(logging, settings.log_level.upper(), logging.INFO),
    format="%(asctime)s - %(levelname)s - %(name)s - %(message)s",
)
logger = logging.getLogger(__name__)


def _verify_dependencies() -> None:
    event_processor_url = settings.event_processor_url.rstrip("/")
    redis_host = settings.redis_host
    redis_port = settings.redis_port

    logger.info("Verifying external dependencies...")
    try:
        response = requests.get(f"{event_processor_url}/health", timeout=2)
        if response.status_code == 200:
            logger.info("Event processor healthy at %s", event_processor_url)
        else:
            logger.warning(
                "Event processor reachable but unhealthy (status=%s)",
                response.status_code,
            )
    except Exception:
        logger.warning("Event processor not reachable at %s", event_processor_url)

    try:
        import redis

        redis.Redis(
            host=redis_host,
            port=redis_port,
            socket_connect_timeout=2,
            password=settings.redis_password,
        ).ping()
        logger.info("Redis reachable at %s:%s", redis_host, redis_port)
    except Exception:
        logger.warning("Redis not reachable at %s:%s", redis_host, redis_port)


def _print_startup_banner(host: str, port: int) -> None:
    docs_url = f"http://{host}:{port}{settings.api_prefix}/docs"
    health_url = f"http://{host}:{port}{settings.api_prefix}/health"
    ws_url = f"ws://{host}:{port}{settings.api_prefix}/ws/alerts/{{user_id}}?token=<access_token>"

    print("\n" + "=" * 72)
    print("SafeHer API (FastAPI)")
    print("=" * 72)
    print(f"Environment: {settings.environment}")
    print(f"API Base:    http://{host}:{port}{settings.api_prefix}")
    print(f"Docs:        {docs_url}")
    print(f"Health:      {health_url}")
    print(f"Realtime:    {ws_url}")
    print("=" * 72 + "\n")


def main() -> None:
    host = os.getenv("API_HOST", settings.api_host)
    port = int(os.getenv("API_PORT", settings.api_port))
    reload_enabled = settings.environment == "development"

    _print_startup_banner(host, port)
    _verify_dependencies()

    uvicorn.run(
        "fastapi_app.main:app",
        host=host,
        port=port,
        reload=reload_enabled,
        log_level=settings.log_level.lower(),
    )


if __name__ == "__main__":
    main()
