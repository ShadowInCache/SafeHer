# Project Structure

SafeHer is a monorepo of parts that share a git history but not a runtime: a
**backend** (`fastapi_app/`), a **mobile app** (`mobile/`), a **smart glove**
(`glove/`), and a set of supporting systems (offline ML training, older device
firmware, cloud functions, deployment).

See [ARCHITECTURE.md](ARCHITECTURE.md) for how these pieces actually talk to
each other at runtime.

```text
SafeHer/
├── fastapi_app/       Backend — FastAPI, the only backend mobile/ talks to
├── mobile/            Flutter app (Riverpod + GoRouter), every screen
├── glove/             Smart glove — firmware, dataset, and the ML pipeline
├── ml_training/       Offline training for the server-side models
├── hardware/          Earlier ESP32 sketches (glove over MQTT, smart glasses)
├── cloud_functions/   Serverless inference (motion/voice/weapon/fusion)
├── deployment/        Docker Compose stack, service configs, SQL
├── alembic/           Database migrations — 13, reversible
├── tests/             Backend test suite (pytest)
├── scripts/           Operational scripts
├── docs/              Every project document, plus archive/ (superseded)
├── app.py             Backend entrypoint — launches fastapi_app via uvicorn
├── manage.py          Docker Compose process manager (start/stop/status/logs)
└── Makefile           Convenience commands (see SETUP.md)
```

Only `README.md` and `LICENSE` remain as documentation at the root. Every other
document moved into `docs/` on 2026-08-21 — eleven markdown files at the top
level made the repo hard to scan, and none of them was load-bearing there.
`fastapi_app/`, `mobile/`, `alembic/` and `tests/` deliberately did **not**
move: `fastapi_app.main:app` is the import path the deployment, Dockerfile,
Makefile and every test rely on, and relocating it would buy tidiness at the
cost of the one thing that has to keep working.

> **On `glove/` and `hardware/esp32_glove/`.** Both are glove firmware and they
> are not the same generation. `hardware/esp32_glove/smart_glove.ino` publishes
> raw telemetry to the backend over MQTT and does no inference. `glove/` runs
> the model on the ESP32 and talks to the phone over BLE with no server in the
> path. `glove/` is the one the app pairs with; `hardware/` is kept because the
> MQTT ingestion path still exists in the backend.

---

## `fastapi_app/` — the backend

14 routers, 73 routes, all mounted under `/api/v1`.

```text
fastapi_app/
├── main.py            App factory: CORS, middleware, router mounts, startup hooks
├── config.py          Settings (pydantic-settings, reads .env) + validate_secrets
├── db.py              Async SQLAlchemy engine/session + SQLite auto-repair guard
├── deps.py            Shared FastAPI dependencies
├── models.py          ORM models
├── schemas.py         Pydantic request/response models
├── security.py        JWT issuing/verification, password hashing, role guards
├── rate_limit.py      Per-route throttling
├── mqtt_service.py    Ingests device telemetry over MQTT (asyncio-mqtt)
├── realtime.py        In-process WebSocket broadcast manager
├── repositories/      Data access, one module per table
│   └── auth_security · devices · emergency_contacts · fcm_tokens
│       notification_logs · safety · users
├── services/
│   ├── emergency_dispatch.py   Contact fan-out: SMS → email → push, 3 attempts each
│   ├── evidence_store.py       AES-256-GCM sealing before any backend sees a byte
│   ├── evidence_backends.py    Where sealed evidence actually lands
│   ├── threat_fusion.py        Combines modality scores into one threat value
│   ├── threat_models.py        Model registry and readiness reporting
│   ├── incident_pdf.py         Forensic export with per-recording SHA-256
│   ├── incident_summary.py     Plain-sentence "why it fired"
│   ├── brevo_email.py          Email over HTTPS — see SETUP.md for why not SMTP
│   ├── smtp_email.py · email.py · onesignal.py · sms.py
│   ├── contact_verification.py · places.py
│   ├── firebase_auth.py        Verifies Firebase ID tokens
│   ├── notifications.py        FCM push
│   └── processor_client.py     HTTP client to the external threat processor
├── workers/
│   └── deletion_purge.py       Hourly purge of accounts past the 30-day grace
└── routers/
    ├── auth.py (12)      users.py (10)     journeys.py (9)   alerts.py (8)
    ├── safety.py (7)     incidents.py (5)  shares.py (5)     devices.py (4)
    ├── health.py (4)     media.py (4)      dashboard.py (2)  notifications.py (2)
    └── ws.py (1)
```

Route counts in parentheses. Full endpoint list: [API.md](API.md).

---

## `mobile/` — the Flutter app

263 Dart files. Full detail in [mobile/README.md](../mobile/README.md).

```text
mobile/lib/
├── main.dart          Bootstrap: Firebase, DI, Hive, ProviderScope, MaterialApp.router
├── core/
│   ├── background/      Foreground service — keeps glove detection alive off screen
│   ├── detection/       What is actually detecting, and its honest limits
│   ├── security/        App lock, certificate pinning
│   ├── evidence/        Recording + encryption before upload
│   ├── offline/         Action queue that replays on reconnect
│   ├── sensors/         Shake detector
│   ├── voice/           On-device command recognition
│   ├── local/           Hive wrappers, user preferences
│   ├── network/         Dio client + interceptors
│   ├── router/          GoRouter table — all navigation goes through it
│   ├── theme/           Design tokens: colour, typography, spacing, radius
│   ├── location/ session/ connectivity/ biometrics/ platform/ animations/ di/
├── features/          data/ → domain/ → presentation/ in each
│   ├── auth/ home/ dashboard/ devices/ monitoring/ emergency/
│   └── reports/ search/ contacts/ profile/ settings/ safety/
└── shared/
    ├── components/      SaCard, SaButton, SaIcon, Sa3DModelViewer, …
    └── models/          Models shared across features
```

`mobile/test/` mirrors `lib/` — 90 test files, 747 tests. Fakes live in
`test/test_utils/`.

---

## `glove/` — the smart glove

The only detector in the system that currently produces real scores. Full
detail in [glove/README.md](../glove/README.md).

```text
glove/
├── firmware/SafeHer_Glove_V5_OnDevice/
│   ├── SafeHer_Glove_V5_OnDevice.ino   100 Hz sampling, 51 features, BLE notify
│   └── safeher_v5_model.{h,cpp}        Generated from the trained model
├── ml/
│   ├── dataset/     Labelled recordings — 140 across 7 classes
│   ├── features/    51 features per 1-second window
│   ├── models/      XGBoost model + column/label/split metadata
│   └── scripts/     collect → extract → train → evaluate → convert
└── docs/            Conversion and deployment reports
```

The BLE contract is duplicated by necessity in two codebases:
`SafeHer_Glove_V5_OnDevice.ino` and
`mobile/lib/features/devices/domain/glove_protocol.dart`. The Dart side is
pinned by tests carrying the firmware's literal payloads; nothing can check the
firmware side automatically.

---

## `ml_training/` — offline training for the server-side models

Independent of the backend — no imports in either direction. Distinct from
`glove/ml/`, which trains the model that runs on the ESP32.

```text
ml_training/
├── motion_detection/    train_motion_model.py → xgboost_motion_model.json
├── voice_detection/     Voice distress detection
├── weapon_detection/    YOLO-based weapon detection (torch/ultralytics)
└── utils/               Shared training utilities
```

Not reproducible from a fresh clone — the raw dataset it expects at
`dataset/raw/*.csv` is not committed.

---

## `hardware/` — earlier device firmware

```text
hardware/
├── esp32_glove/smart_glove.ino      MPU6050 + panic button, MQTT over TLS
└── smart_glasses/smart_glasses.ino  ESP32-CAM frame streaming
```

The mobile UI also shows a "Smart Ring" and "Pendant". Those are product-vision
mockups with no firmware anywhere in this repo.

---

## `cloud_functions/` — serverless inference

Four independently-deployable functions (`deploy.sh`), each with its own
`requirements.txt`: `motion_detection/`, `voice_analysis/`,
`weapon_detection/`, and `threat_fusion/`, which combines the other three into
one score.

---

## `deployment/`

```text
deployment/
├── docker/
│   ├── docker-compose.yml    Postgres + Redis + Mosquitto + one event processor
│   ├── Dockerfile.processor, safeher_event_processor.py, event_system/
│   └── requirements.simple.txt
├── config/
│   ├── mosquitto.conf, redis.conf, ssl/   Used by the compose stack
│   └── nginx.conf, prometheus.yml          Left from an earlier multi-service
│                                            design; not wired into anything
└── scripts/start_all_services.ps1
```

---

## `tests/` — backend

31 files, **409 passing and 7 skipped**. Most drive the ASGI app directly
through `httpx.ASGITransport` and need no running server.

Two files are the exception: `test_api_gateway.py` and `test_integration.py`
hit a live backend over `requests`, so start one first or they fail on
connection.

Two tests earn a special mention because they police the documentation itself:

- **`test_traceability.py`** — every requirement in `SRS.md` must have a row in
  [TRACEABILITY.md](TRACEABILITY.md), every path a row names must exist, and a
  row marked *not built* may not cite an implementation. Renaming a file that a
  requirement points at fails the suite.
- **`test_health_endpoints.py`** — `/health` must stay constant-time. It is
  what uptime monitoring points at, and a cold call to `/status` once timed out
  at 40 seconds.

CI runs migrations against a **real Postgres 16 service**, not SQLite. That was
added after a migration containing `is_verified = 1` passed the entire suite
and then failed on production Postgres with *"operator does not exist: boolean
= integer"*, aborting mid-chain with the schema half-applied.

---

## `docs/`

```text
docs/
├── SRS.md                The governing spec
├── SRS_STATUS.md         How much of it is actually built, with a session log
├── ARCHITECTURE.md       How the pieces fit
├── API.md                Every endpoint, shape and auth requirement
├── SETUP.md              Setup and troubleshooting
├── SECURITY.md           Threat model, secrets, known limitations
├── TRACEABILITY.md       Requirement → code, enforced by a test
├── PROJECT_STRUCTURE.md  This file
├── MEMORY.md             Append-only change history
├── CHANGELOG.md · CONTRIBUTING.md · DEPENDENCIES.md
└── archive/              Every doc predating the 2026-08-08 audit, verbatim
```
