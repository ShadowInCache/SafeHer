# Project Structure

SafeHer is a monorepo with three independent parts that share a git history but not a
runtime: a **current backend** (`fastapi_app/`), a **mobile frontend** (`mobile/`), and
a set of **supporting systems** (ML training, device firmware, cloud functions,
deployment). A **legacy backend** (`legacy_flask_gateway/`) is kept for reference only.
See [ARCHITECTURE.md](ARCHITECTURE.md) for how these pieces actually talk to each
other at runtime.

```text
SafeHer/
├── fastapi_app/          Current backend — FastAPI, the only backend fastapi/mobile talk to
├── mobile/                Flutter frontend (Riverpod + GoRouter), all UI screens
├── legacy_flask_gateway/  Superseded Flask backend, kept for reference — not deployed
├── ml_training/           Offline model-training scripts + trained artifacts (XGBoost, voice, weapon)
├── hardware/               ESP32 firmware for the two physical devices (glove, glasses)
├── cloud_functions/       Multi-cloud serverless functions (motion/voice/weapon/fusion)
├── deployment/             Docker Compose stack, service configs, startup scripts
├── alembic/                Database migrations (SQLAlchemy schema history)
├── tests/                  Backend test suite (pytest)
├── scripts/                One-off operational scripts
├── docs/                   Documentation, including docs/archive/ (superseded reports)
├── app.py                  Backend entrypoint — launches fastapi_app via uvicorn
├── manage.py                Docker Compose process manager (start/stop/status/logs)
├── validate_dataset.py     Standalone validator for the ML training dataset
├── requirements.txt         Python dependencies (see DEPENDENCIES.md)
├── alembic.ini               Alembic configuration
├── supabase_setup.sql        Schema for the Supabase events-archive table
└── Makefile                  Convenience commands (see SETUP.md)
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

## `legacy_flask_gateway/` — superseded backend, reference only

Originally `src/`, renamed and relocated during the 2026-08-08 audit for clarity. This
is the Flask-based backend that `fastapi_app/` replaced. Nothing in `fastapi_app/`,
`mobile/`, `tests/`, or `deployment/`'s active compose file imports or runs it anymore
— `legacy_flask_gateway/services/database/db_service.py` even raises on
instantiation with a comment pointing at the new SQLAlchemy models. Kept rather than
deleted because it documents real, previously-working business logic (its own
WebSocket manager, orchestrator, and Supabase-archive endpoints) that hasn't been
fully re-verified as present in `fastapi_app/`.

```text
legacy_flask_gateway/
├── core/            Flask app (api_gateway.py), orchestrator, websocket_manager
├── services/         Raw-sqlite db_service (deprecated/raises), its own MQTT service
└── utils/             Flask-era auth, config, logger, validators
```

## `ml_training/` — offline model training (originally `src/models/`)

Independent of both backends — no imports from `fastapi_app/` or
`legacy_flask_gateway/` in either direction.

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

`test_fastapi_contracts.py` and parts of `test_api_gateway.py`/`test_integration.py`
exercise the live `fastapi_app` routes. `test_authentication.py` and
`test_microservices.py` predate the current architecture (interactive script; ports
for standalone services that no longer exist) — see AUDIT_REPORT.md for details before
relying on them. Mobile tests live under `mobile/test/`, mirroring `mobile/lib/`.

## `docs/`

```text
docs/
├── archive/    Every doc that existed before the 2026-08-08 audit, preserved verbatim
└── (this file, ARCHITECTURE.md, API.md, SETUP.md, SECURITY.md, etc. live at repo root)
```
