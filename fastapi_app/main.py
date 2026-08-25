import asyncio
import logging
import time

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

from fastapi_app.rate_limit import DEFAULT_RULES, SlidingWindowLimiter, client_key

from fastapi_app.config import get_settings
from fastapi_app.db import init_db
from fastapi_app.workers.deletion_purge import deletion_purge_worker
from fastapi_app.routers import (
    alerts,
    auth,
    dashboard,
    devices,
    health,
    incidents,
    journeys,
    media,
    notifications,
    safety,
    shares,
    users,
    ws,
)
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


# Enabled outside development so the test suite and local work are not
# throttled while creating accounts. The limiter object is module-level so a
# test can reach in, force it on, and assert the behaviour directly.
rate_limiter = SlidingWindowLimiter(DEFAULT_RULES)
rate_limiting_enabled = not is_development


@app.middleware("http")
async def rate_limit_middleware(request: Request, call_next):
    if rate_limiting_enabled:
        retry_after = rate_limiter.check(client_key(request), request.url.path)
        if retry_after is not None:
            logger.warning(
                "Rate limit hit: %s %s", request.method, request.url.path
            )
            return JSONResponse(
                status_code=429,
                content={"detail": "Too many requests. Please try again shortly."},
                headers={"Retry-After": str(retry_after)},
            )
    return await call_next(request)


@app.middleware("http")
async def security_headers_middleware(request: Request, call_next):
    """Defensive headers.

    This API serves JSON to a mobile client, so most of these are belt and
    braces -- but the share-link routes are opened in a browser, and the
    OpenAPI docs render HTML, so the surface is not zero.

    `frame-ancestors 'none'` and X-Frame-Options are the pair that matter for
    clickjacking; nosniff stops a JSON response being coaxed into executing as
    something else; the referrer policy keeps share tokens out of the Referer
    header when a shared page links onward.
    """
    response = await call_next(request)
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("X-Frame-Options", "DENY")
    response.headers.setdefault("Referrer-Policy", "no-referrer")
    response.headers.setdefault(
        "Content-Security-Policy",
        "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
    )
    if not is_development:
        # Only meaningful over TLS, and actively unhelpful on a local http
        # server, where it would pin the browser to https for localhost.
        response.headers.setdefault(
            "Strict-Transport-Security", "max-age=31536000; includeSubDomains"
        )
    return response


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
    # `exc.headers` must be forwarded: it carries `Retry-After` on rate-limit
    # and lockout responses, and `WWW-Authenticate` on 401s. Dropping it makes
    # those responses unactionable for clients.
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail},
        headers=exc.headers,
    )


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
app.include_router(dashboard.router)
app.include_router(safety.router)
app.include_router(journeys.router)
app.include_router(shares.router)


@app.on_event("startup")
async def on_startup() -> None:
    await init_db()
    if settings.enable_mqtt_worker:
        app.state.mqtt_task = asyncio.create_task(mqtt_worker())
        logger.info("MQTT worker launched")
    else:
        app.state.mqtt_task = None
        logger.info("MQTT worker disabled by configuration")

    app.state.deletion_purge_task = asyncio.create_task(deletion_purge_worker())
    logger.info("Account deletion purge worker launched")


@app.on_event("shutdown")
async def on_shutdown() -> None:
    for attr in ("mqtt_task", "deletion_purge_task"):
        task = getattr(app.state, attr, None)
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
