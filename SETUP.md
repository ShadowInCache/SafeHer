# Setup

## Prerequisites

- **Python 3.11+** — backend and ML training scripts
- **Flutter 3.x** (Dart `>=3.8.0 <4.0.0`, see `mobile/pubspec.yaml`) — mobile app
- **Docker + Docker Compose** — if you want the full local stack (Postgres, Redis,
  Mosquitto) instead of running the backend against a bare SQLite file
- **A Supabase project** — optional, only needed for the events-archive feature

## 1. Clone and install

```bash
git clone https://github.com/ShadowInCache/SafeHer.git
cd SafeHer
pip install -r requirements.txt
```

`requirements.txt` covers three concerns in one file: the current FastAPI backend, the
archived Flask gateway (`legacy_flask_gateway/`), and the ML training pipeline
(`ml_training/`). You don't need the ML stack (`torch`, `ultralytics`, `librosa`, ...)
just to run the backend — see [DEPENDENCIES.md](DEPENDENCIES.md) if you want to trim
your local install.

## 2. Environment variables

```bash
cp .env.example .env
```

Then fill in real values. Grouped by concern:

| Group | Variables | Notes |
|---|---|---|
| Core | `API_HOST`, `API_PORT`, `DEBUG`, `LOG_LEVEL` | Defaults work for local dev (`API_PORT=5000`) |
| Database | `DATABASE_URL` | Defaults to SQLite (`sqlite:///./safeher.db`) if unset; use a `postgresql://` URL for Postgres |
| Supabase | `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY` | Only required if you use the events-archive feature. **Never commit real values** — see [SECURITY.md](SECURITY.md) |
| Redis | `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` | Used by the event-processing pipeline |
| MQTT | `MQTT_HOST`, `MQTT_PORT`, `MQTT_USERNAME`, `MQTT_PASSWORD` | Needed if you're testing against real/simulated device firmware |
| Auth | `JWT_SECRET_KEY`, `JWT_ISSUER`, `JWT_AUDIENCE`, `ACCESS_TOKEN_EXPIRE_MINUTES`, `REFRESH_TOKEN_EXPIRE_DAYS` | `JWT_SECRET_KEY` **must** be a strong, non-default value in staging/production — `fastapi_app/config.py` refuses to start otherwise |
| Notifications | `FCM_SERVER_KEY`, `TWILIO_*` | Optional — push/SMS silently no-op if unset |
| Storage | `CLOUDINARY_*` | Optional — `/api/v1/media/sign-upload` returns 400 if unset |
| Maps | `GOOGLE_MAPS_API_KEY` | Used by the mobile app |
| CORS | `ALLOW_ORIGINS` | Comma-separated list |

## 3. Run the backend

**Option A — Docker Compose (recommended, matches production topology):**
```bash
python manage.py start      # brings up Postgres, Redis, Mosquitto, event processor
python manage.py status
python manage.py logs
python manage.py stop
```

**Option B — bare backend, no Docker (fastest inner loop):**
```bash
python app.py
```
This talks to whatever `DATABASE_URL` points at (SQLite by default) and warns —
without failing — if Redis or the event processor aren't reachable.

Apply database migrations if you're not starting from a fresh SQLite file:
```bash
alembic upgrade head
```

Verify it's up:
```bash
curl http://localhost:5000/api/v1/health
```

## 4. Run the mobile app

```bash
cd mobile
flutter pub get
flutter run                     # picks a connected device/emulator
flutter run -d chrome           # or run in a browser
flutter run -d web-server --web-port=8765   # headless web server, for automated screenshots
```

The mobile app defaults to mock repositories (`AppFlavor.isMock`) — it does not
require the backend to be running to explore the UI. See [ARCHITECTURE.md](ARCHITECTURE.md)
for which parts are wired to `fastapi_app/` already.

## 5. Run the ML training pipeline (optional)

```bash
python validate_dataset.py           # checks for a dataset/raw/*.csv tree — not committed
python ml_training/motion_detection/train_motion_model.py
```

`validate_dataset.py` will fail its dataset checks on a fresh clone — the raw training
data referenced by `ml_training/motion_detection/train_motion_model.py` isn't part of
this repo. You need your own labeled dataset to reproduce `xgboost_motion_model.json`.

## Development workflow

```bash
make help          # list convenience targets
make install        # pip install -r requirements.txt
make clean           # remove __pycache__, *.pyc, ml_training/outputs/*, flutter build artifacts
make flutter-setup    # flutter pub get
make flutter-run       # flutter run
make flutter-build      # flutter build apk --release
```

Note: `make setup`, `make train`, and `make test` reference `scripts/setup.py`,
`scripts/train_all.py`, and `scripts/test_apis.py`, which don't currently exist in
`scripts/` (only `scripts/smoke_firebase_exchange.py` does) — those three targets will
fail until those scripts are added. Use the commands in this file directly instead.

## Testing

```bash
# Backend
pytest tests/                              # some files are stale, see PROJECT_STRUCTURE.md
pytest tests/test_fastapi_contracts.py     # the reliable one — runs in-process, no server needed

# Mobile
cd mobile
flutter analyze
flutter test
```

## Troubleshooting

- **"JWT_SECRET_KEY must be set" on startup** — you're running with
  `ENVIRONMENT=production` or `staging` and either didn't set `JWT_SECRET_KEY` or left
  it as `change-me`. Set a real secret, or run with `ENVIRONMENT=development` locally.
- **SQLite "database is locked" or schema errors** — `fastapi_app/db.py` has an
  auto-repair guard that backs up and recreates a stale-schema SQLite file; if you hit
  this in dev, it's usually safe to delete the local `safeher.db` and let migrations
  recreate it (`alembic upgrade head`).
- **`/api/v1/media/sign-upload` returns 400 "Cloudinary is not configured"** — set the
  three `CLOUDINARY_*` variables in `.env`.
- **Event processor "not reachable" warning on `python app.py` startup** — expected if
  you haven't started `deployment/docker/docker-compose.yml`'s event-processor
  container; the backend still starts, threat processing just won't have a live
  processor to call.
- **Mobile: blank white screen after `flutter run -d web-server`** — this is normal on
  first load. Flutter web (debug/dartdevc) compiles ~900 modules on first request,
  which can take 10–20 seconds before the first paint. It's not a hang.
- **`mobile-ci.yml` never triggers** — fixed as of the 2026-08-08 audit; it previously
  filtered on `SafeHer/mobile/**` paths that never matched (the repo root already *is*
  `SafeHer`), so it silently never ran. It now filters on `mobile/**`.
