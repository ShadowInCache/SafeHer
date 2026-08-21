# Project Structure

SafeHer is a monorepo with three independent parts that share a git history but not a
runtime: a **current backend** (`fastapi_app/`), a **mobile frontend** (`mobile/`), and
a set of **supporting systems** (ML training, device firmware, cloud functions,
deployment).
See [ARCHITECTURE.md](ARCHITECTURE.md) for how these pieces actually talk to each
other at runtime.

```text
SafeHer/
├── fastapi_app/          Current backend — FastAPI, the only backend fastapi/mobile talk to
├── mobile/                Flutter frontend (Riverpod + GoRouter), all UI screens
├── ml_training/           Offline model-training scripts + trained artifacts (XGBoost, voice, weapon)
├── hardware/               ESP32 firmware for the two physical devices (glove, glasses)
├── cloud_functions/       Multi-cloud serverless functions (motion/voice/weapon/fusion)
├── deployment/             Docker Compose stack, service configs, startup scripts,
│                            and sql/supabase_setup.sql (events-archive schema)
├── alembic/                Database migrations (SQLAlchemy schema history)
├── tests/                  Backend test suite (pytest)
├── scripts/                One-off operational scripts, incl. validate_dataset.py
├── docs/                   All project documentation — SRS.md, API.md, ARCHITECTURE.md,
│                            SETUP.md, SECURITY.md, MEMORY.md, plus archive/ (superseded)
├── app.py                  Backend entrypoint — launches fastapi_app via uvicorn
├── manage.py                Docker Compose process manager (start/stop/status/logs)
├── requirements.txt         Python dependencies (see docs/DEPENDENCIES.md)
├── alembic.ini               Alembic configuration
├── README.md                 Orientation; everything else lives in docs/
└── Makefile                  Convenience commands (see docs/SETUP.md)

Only README.md and LICENSE remain as documentation at the root. Every other
document moved into `docs/` on 2026-08-21 — eleven markdown files at the top
level made the repo hard to scan, and none of them was load-bearing there.
`fastapi_app/`, `mobile/`, `alembic/` and `tests/` deliberately did **not**
move: `fastapi_app.main:app` is the import path the deployment, Dockerfile,
Makefile and every test rely on, and relocating it would buy tidiness at the
cost of the one thing that has to keep working.
```

## `fastapi_app/` — current backend

```text
fastapi_app/
├── main.py                 App factory: CORS, middleware, router mounts, startup hooks
├── config.py                 Settings (pydantic-settings, reads .env)
├── db.py                     Async SQLAlchemy engine/session + SQLite auto-repair guard
├── deps.py                   Shared FastAPI dependencies
├── models.py                 ORM models: User, Incident, Device, Location, Media,
│                              NotificationLog, FcmToken, EmergencyContact
├── schemas.py                 Pydantic request/response models
├── security.py                 JWT issuing/verification, password hashing, role guards
├── mqtt_service.py            Ingests device telemetry over MQTT (asyncio-mqtt)
├── realtime.py                 In-process WebSocket broadcast manager
├── repositories/               Data-access functions, one module per table
│   ├── users.py, devices.py, emergency_contacts.py, fcm_tokens.py, notification_logs.py
├── services/
│   ├── firebase_auth.py        Verifies Firebase ID tokens for the auth/firebase/exchange flow
│   ├── notifications.py         Sends FCM push notifications
│   └── processor_client.py      HTTP client to the external threat-processing service
└── routers/                    One module per resource, all mounted under /api/v1
    ├── health.py, auth.py, users.py, media.py, incidents.py
    ├── devices.py, notifications.py, alerts.py, ws.py
```

Full endpoint list: [API.md](API.md).

## `mobile/` — Flutter frontend

```text
mobile/lib/
├── main.dart                App bootstrap: DI, Hive init, ProviderScope, MaterialApp.router
├── core/
│   ├── router/                GoRouter route table (all navigation goes through this)
│   ├── theme/                  Design tokens: colors, typography, spacing, radius, shadows
│   ├── network/                 Dio client + interceptors
│   ├── local/                    Hive box wrappers (LocalKeyValueStore)
│   ├── offline/                   Offline action queue + retry
│   ├── connectivity/               ConnectivityNotifier (online/offline state)
│   ├── animations/                  Reduced-motion-aware animation helpers
│   └── di/                            get_it service locator setup
├── features/                One folder per screen/domain, each with data/domain/presentation
│   ├── auth/, home/, dashboard/, devices/, monitoring/, emergency/
│   ├── reports/, search/, contacts/, profile/, settings/
└── shared/
    ├── components/            Reusable widgets (SaCard, SaButton, SaIcon, Sa3DModelViewer, ...)
    └── models/                 Shared data models used across features
```

Each `features/<name>/` follows Clean Architecture: `data/` (repositories, mock or real),
`domain/` (entities, use cases), `presentation/` (screens, widgets, Riverpod
controllers). See `mobile/test/` for the mirrored test tree.

## `ml_training/` — offline model training (originally `src/models/`)

Independent of the backend — no imports from `fastapi_app/` in either direction.

```text
ml_training/
├── motion_detection/    train_motion_model.py — produces xgboost_motion_model.json
│                         and motion_training_results.json (both currently committed
│                         at repo root; the raw training dataset itself is not in the repo)
├── voice_detection/       Voice distress-detection training
├── weapon_detection/       Weapon/threat detection training (torch/ultralytics/opencv)
└── utils/, gpu_utils.py     Shared training utilities
```

## `hardware/` — device firmware

```text
hardware/
├── esp32_glove/smart_glove.ino     MPU6050 motion sensing, panic button, MQTT over TLS
└── smart_glasses/smart_glasses.ino ESP32-CAM frame streaming for edge weapon detection
```

Only these two physical devices have real firmware. The mobile app's UI also shows a
"Smart Ring" and "Pendant" as devices — those are product-vision mockups with no
corresponding firmware in this repo (see [ARCHITECTURE.md](ARCHITECTURE.md#known-gaps)).

## `cloud_functions/` — serverless inference

Four independently-deployable functions (AWS Lambda / GCP / Azure via `deploy.sh`),
each with its own `requirements.txt`: `motion_detection/`, `voice_analysis/`,
`weapon_detection/`, `threat_fusion/` (combines the other three into one threat score).

## `deployment/`

```text
deployment/
├── docker/
│   ├── docker-compose.yml         Current stack: Postgres + Redis + Mosquitto + one
│   │                                unified "safeher_event_processor" container
│   ├── Dockerfile.processor, safeher_event_processor.py, event_system/
│   └── requirements.simple.txt
├── config/
│   ├── mosquitto.conf, redis.conf, ssl/    Used by the current compose stack
│   └── nginx.conf, prometheus.yml           Left over from an earlier multi-service
│                                              design the compose file's own comments
│                                              mark "REMOVED" — not wired into anything
│                                              currently running (see AUDIT_REPORT.md)
└── scripts/start_all_services.ps1  Windows helper to launch the compose stack
```

## `tests/` (backend, pytest)

Two classes of test live here.

**In-process (no server needed)** — the reliable set, 67 tests total:
`test_fastapi_contracts.py`, `test_safety_contracts.py`, `test_auth_security.py`
(SRS section 4.1 auth behaviour), `test_auth_provisioning.py` and
`test_firebase_token_verification.py`. These drive the ASGI app directly via
`httpx.ASGITransport`.

**Live-server (HTTP)** — `test_api_gateway.py` and `test_integration.py` hit a running
backend over `requests`; start it first or they fail on connection.

`test_authentication.py` (broken `token` fixture) and `test_microservices.py` (targeted
standalone services on ports 8001-8004 that no longer exist, so all 8 tests skipped
unconditionally) were deleted on 2026-08-15.

Mobile tests live under `mobile/test/`, mirroring `mobile/lib/`.

## `docs/`

```text
docs/
├── archive/    Every doc that existed before the 2026-08-08 audit, preserved verbatim
└── (this file, ARCHITECTURE.md, API.md, SETUP.md, SECURITY.md, etc. live at repo root)
```
