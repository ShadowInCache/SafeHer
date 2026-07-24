import asyncio
import logging
import time

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

from fastapi_app.config import get_settings
from fastapi_app.db import init_db
from fastapi_app.routers import alerts, auth, devices, health, incidents, media, notifications, users, ws
from fastapi_app.mqtt_service import mqtt_worker


settings = get_settings()
logging.basicConfig(
    level=getattr(logging, settings.log_level.upper(), logging.INFO),
    format="%(asctime)s - %(levelname)s - %(name)s - %(message)s",
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title=settings.app_name,
    debug=settings.debug,
    version="1.0.0",
    docs_url=f"{settings.api_prefix}/docs",
    redoc_url=f"{settings.api_prefix}/redoc",
    openapi_url=f"{settings.api_prefix}/openapi.json",
)

is_development = settings.environment.lower() == "development"

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if is_development else settings.allow_origins,
    allow_origin_regex=None if is_development else settings.allow_origin_regex,
    allow_credentials=False if is_development else True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def request_logging_middleware(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    duration_ms = (time.perf_counter() - start) * 1000
    logger.info(
        "%s %s -> %s (%.2f ms)",
        request.method,
        request.url.path,
        response.status_code,
        duration_ms,
    )
    return response


@app.exception_handler(HTTPException)
async def http_exception_handler(_: Request, exc: HTTPException):
    return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})


@app.exception_handler(Exception)
async def unhandled_exception_handler(_: Request, exc: Exception):
    logger.exception("Unhandled server exception")
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(users.router)
app.include_router(media.router)
app.include_router(incidents.router)
app.include_router(devices.router)
app.include_router(ws.router)
app.include_router(notifications.router)
app.include_router(alerts.router)


@app.on_event("startup")
async def on_startup() -> None:
    await init_db()
    if settings.enable_mqtt_worker:
        app.state.mqtt_task = asyncio.create_task(mqtt_worker())
        logger.info("MQTT worker launched")
    else:
        app.state.mqtt_task = None
        logger.info("MQTT worker disabled by configuration")


@app.on_event("shutdown")
async def on_shutdown() -> None:
    task = getattr(app.state, "mqtt_task", None)
    if task:
        task.cancel()
        try:
            await task
        except Exception:
            pass


@app.get("/")
def root():
    return {
        "service": settings.app_name,
        "status": "ready",
        "api_prefix": settings.api_prefix,
        "docs": f"{settings.api_prefix}/docs",
    }
