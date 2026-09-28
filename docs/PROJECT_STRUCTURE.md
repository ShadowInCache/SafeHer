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
├── glasses/           Smart glasses — streaming firmware, no model on board
├── ml_models/         Server-side ONNX for the web weapon fallback
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

> **Several glove sketches, one folder.** `glove/firmware/SafeHer_Glove_V5_OnDevice/`
> is the sketch to flash: it carries the current **5-class** model
> (`PUSH`/`PULL`/`JERK` merged into `SUDDEN_MOVEMENT`) and the payload
> (`FALL,0.93`). Check `DATA_COLLECTION_MODE` is `0` — at `1` BLE never starts.
> `SafeHer_Glove_Final/` holds the FreeRTOS timing fix (hardware-validated
> 2026-09-10) but still the **retired 7-class model**, with a keyed payload
> (`CLASS=FALL,CONFIDENCE=0.9300`) the app also reads. Alongside them: two diagnostic sketches
> (`SafeHer_Glove_Hardware_Diagnostic/`, `SafeHer_Glove_Inference_Diagnostic/`),
> `SafeHer_Glove_Failure_Capture/`, `SafeHer_Minimal_Test/` (Serial-only
> toolchain check), and `legacy_mqtt/smart_glove.ino` — kept because the MQTT
> ingestion path still exists in the backend.

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

mobile/assets/models/     Trained weights bundled into the app
└── weapon_yolov8n_int8.onnx   3.36 MB — trained, validated, not yet loaded
```

`mobile/test/` mirrors `lib/` — 90 test files, 747 tests. Fakes live in
`test/test_utils/`.

---

## `glove/` — the smart glove

The only detector in the system that currently produces real scores. Full
detail in [glove/README.md](../glove/README.md).

```text
glove/
├── firmware/SafeHer_Glove_V5_OnDevice/          FLASH THIS — 5-class model, app payload
│   ├── SafeHer_Glove_V5_OnDevice.ino            100 Hz sampling, 51 features, BLE notify
│   └── safeher_v5_model.{h,cpp}                 Generated from the 5-class v7 model
├── firmware/SafeHer_Glove_Final/                FreeRTOS timing fix, still 7-class
│   ├── SafeHer_Glove_Final.ino                  Different payload: CLASS=..,CONFIDENCE=..
│   ├── safeher_glove_final_model.{h,cpp}        Retired 7-class V5 model
│   └── HARDWARE_VALIDATION_REPORT.md            Real ESP32-C3 findings (2026-09-10)
├── firmware/SafeHer_Glove_{Hardware,Inference}_Diagnostic/   Bench sketches (7-class)
├── firmware/SafeHer_Glove_Failure_Capture/      Raw capture around a fault (7-class)
├── firmware/SafeHer_Minimal_Test/               Serial-only toolchain check
├── ml/
│   ├── dataset/     5 training classes; push/pull/jerk kept for the 7-class history
│   ├── features/    51 features per 1-second window
│   ├── models/      XGBoost model + column/label/split metadata
│   └── scripts/     collect → extract → train → evaluate → convert
└── requirements.txt
```

The BLE contract is duplicated by necessity in two codebases:
`SafeHer_Glove_V5_OnDevice.ino` and
`mobile/lib/features/devices/domain/glove_protocol.dart`. The Dart side is
pinned by tests carrying the firmware's literal payloads; nothing can check the
firmware side automatically — `scripts/check_glove.py` against a real board is
the only check that does.

---

## `glasses/` — smart glasses firmware

```text
glasses/
├── README.md                            What it serves and why — start here
├── SETUP.md                             Board settings, flashing, verification
└── firmware/
    ├── SafeHer_Glasses_Stream/          CURRENT — MJPEG + audio + mDNS
    ├── legacy_esp32cam/                 Targets a different board, does not compile
    └── legacy_noise_alarm/              Noise alarm that preceded streaming
```

The glasses run no model. They stream VGA MJPEG and 16 kHz audio to the phone,
which scores the frames — an ESP32-S3 is two orders of magnitude short of
YOLOv8n (`WEAPON_INFERENCE_PLACEMENT.md`). The glove is the opposite: it runs
its model on-device and reports a conclusion over BLE.

**One folder per device, current and legacy firmware together.** Until
2026-09-02 the glove lived in two trees — `glove/` for the current BLE firmware
and `hardware/esp32_glove/` for an older MQTT one — which read as duplication
rather than as two generations. The legacy sketches now sit beside the firmware
they succeeded:

```text
glove/firmware/
├── SafeHer_Glove_V5_OnDevice/           CURRENT — 5-class on-device XGBoost over BLE
├── SafeHer_Glove_Final/                 Timing fix on the retired 7-class model
└── legacy_mqtt/smart_glove.ino          Earlier: raw telemetry over MQTT
```

`legacy_mqtt` is kept because the MQTT ingestion path still exists in the
backend. `legacy_esp32cam` is kept for reference only — it includes two headers
that are not in this repository and cannot be built.

The mobile UI also shows a "Smart Ring" and "Pendant". Those are product-vision
mockups with no firmware anywhere in this repo.

---

## Where model training lives

Two places, and only one of them is in this repository.

`glove/ml/` trains the model that runs **on the ESP32** — collect, extract
features, train, evaluate, convert to C arrays. It is here because its output is
compiled into the firmware sitting beside it.

The weapon, audio and expression models are trained **outside the repository**,
because their datasets run to gigabytes. What is committed is only what ships:
`mobile/assets/models/` for on-device artifacts, `ml_models/` for the
server-side ONNX used by the web weapon fallback.

**Two trees were deleted on 2026-09-02.** `ml_training/` trained on `np.random`
synthetic data and left a `motion_training_results.json` reporting 98.17%
accuracy — a model separating two uniform distributions it had generated itself,
and a number nobody should ever quote. `cloud_functions/` implemented an earlier
fusion design that `fastapi_app/services/threat_fusion.py` superseded, was never
deployed, and loaded a `voice_model.pkl` that does not exist.

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

31 files, **468 passing and 7 skipped**. Most drive the ASGI app directly
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
├── assets/               Images the documentation references, incl. the logo
└── archive/              Every doc predating the 2026-08-08 audit, verbatim
```
