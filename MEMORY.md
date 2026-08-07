# Project Memory

This file is the project's long-term memory. Every future modification of consequence
— adding/deleting files, refactoring, renaming, moving folders, dependency changes,
bug fixes — should append an entry under **Change History**, in chronological order.
Never overwrite or delete a prior entry.

## Project Overview

SafeHer is an AI-powered wearable safety platform for women. The repo is a monorepo
containing a current FastAPI backend (`fastapi_app/`), a Flutter mobile app
(`mobile/`), ESP32 device firmware (`hardware/`), an ML training pipeline
(`ml_training/`), serverless inference functions (`cloud_functions/`), a Docker
Compose deployment (`deployment/`), and an archived, unused legacy Flask backend
(`legacy_flask_gateway/`). See [ARCHITECTURE.md](ARCHITECTURE.md) for how the pieces
connect and [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) for the full folder tour.

## Architecture Decisions

- **FastAPI replaced Flask as the backend of record** (date unclear from history,
  before 2026-04-03 per `app.py`'s mtime). The Flask code was never deleted, just left
  in place — this is what the 2026-08-08 audit relocated to `legacy_flask_gateway/`
  rather than removing outright, since it wasn't possible to fully verify feature
  parity between the two within the audit's scope.
- **Mobile app is Riverpod + GoRouter only, no exceptions** — established as an
  absolute rule in the mobile app's original build spec, not something to relax for
  convenience.
- **Mobile app is mock-backed by default** (`AppFlavor.isMock`) — real API wiring to
  `fastapi_app/` is an intentional, incremental migration (Phase 4 of the mobile
  build), not a shortcut.
- **Supabase is an archive layer, not the primary datastore** — Postgres/SQLite via
  SQLAlchemy is the transactional source of truth; Supabase's `events` table
  (`supabase_setup.sql`) is a parallel, append-only archive.

## Folder Changes

- 2026-08-08: `src/models/` → `ml_training/` (top-level rename, no code changes beyond
  path references).
- 2026-08-08: `src/` (remaining: `core/`, `services/`, `utils/`) → `legacy_flask_gateway/`.
- 2026-08-08: `docs/*.md` (8 pre-existing reports) + root `README.md` + `QUICKSTART.py`
  → `docs/archive/`, preserved verbatim (`QUICKSTART.py` renamed to
  `QUICKSTART.py.txt` since it's no longer meant to be executed).

## File Changes

- 2026-08-08: `cloud_functions/voice_analysis/main.py` — updated 4 hardcoded model
  paths from `src/models/...` to `ml_training/...` after the folder rename.
- 2026-08-08: `validate_dataset.py` — updated model-dir path from `src/models/...` to
  `ml_training/...` after the folder rename.
- 2026-08-08: `legacy_flask_gateway/core/__init__.py`, `core/api_gateway.py` — updated
  internal absolute imports from `src.core...`/`src.services...` to
  `legacy_flask_gateway.core...`/`legacy_flask_gateway.services...` after the rename.
- 2026-08-08: `.github/workflows/mobile-ci.yml` — fixed path filters and working
  directory (`SafeHer/mobile/**` → `mobile/**`); the CI job had never actually
  triggered since the repo root already is `SafeHer`. Also fixed
  `flutter analyze lib/main.dart lib/app` (referencing a nonexistent `lib/app` path)
  to a plain `flutter analyze`.
- 2026-08-08: `.gitignore` — expanded from 3 lines (`.env` only) to cover Python
  caches/venvs, `*.db`, browser-automation profiles, and Flutter build artifacts.

## Deleted Files

- 2026-08-08: `audit_system.py` — audited the legacy Flask gateway specifically
  (imported `src.core.api_gateway`, etc.), referenced by nothing else in the repo.
- 2026-08-08: `hardware/esp32_cam/smart_glasses.ino` — byte-identical duplicate of
  `hardware/smart_glasses/smart_glasses.ino`; kept the latter.
- 2026-08-08: `deployment/docker/dy` — a stray cached HTTP 400 error response
  accidentally committed, not source code.
- 2026-08-08: Untracked (not deleted from disk) — `deployment/docker/.env` (leaked
  secrets, see Security below), `mobile/.chrome_fresh_profile/` (~3,150 files, an
  accidentally-committed Chrome browser profile), `safeher.db`, `safeher.runtime.db`,
  `safeher_app.db`, `test_safeher.db`, all `__pycache__/` directories (71 files).

## Added Files

- 2026-08-08: Full documentation set — `README.md`, `ARCHITECTURE.md`, `API.md`,
  `SETUP.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `DEPENDENCIES.md`,
  `PROJECT_STRUCTURE.md`, `SECURITY.md`, `MEMORY.md` (this file). `docs/archive/README.md`
  explaining the archive's contents.

## Refactored Modules

- 2026-08-08: No behavioral refactors performed — only relocations (see Folder
  Changes) with corresponding import/path fixes to preserve functionality. Deeper
  structural refactors (e.g. resolving the `paho-mqtt`/`asyncio-mqtt` duplication, or
  splitting `requirements.txt` by concern) were identified but intentionally left for
  a follow-up pass — see Pending Tasks.

## Dependency Changes

- 2026-08-08: `requirements.txt` — removed duplicate `alembic==1.13.1` and duplicate
  bare `redis==5.0.1` lines (the `redis[hiredis]` extras line already covers it). No
  packages added or removed, and nothing changed in `mobile/pubspec.yaml`. See
  [DEPENDENCIES.md](DEPENDENCIES.md) for the full audit findings, including an
  unconfirmed `opencv-python` usage question left as-is pending closer verification.

## Documentation Changes

- 2026-08-08: Complete documentation rebuild. Prior docs (46KB root `README.md`, 8
  files in `docs/`) were largely stale/aspirational — describing a `backend/`/`frontend/`
  split that never existed, Flask-on-port-5000, RabbitMQ/TimescaleDB/Kubernetes/
  Prometheus/Grafana that aren't in the repo, and fabricated metrics (93% mAP, 99.9%
  uptime, $235/month, 500+ commits, 4-person team) contradicted by the project's own
  other reports. Archived rather than deleted (docs/archive/), new docs written from
  direct source-code inspection.

## Bugs Fixed

- 2026-08-08: `.github/workflows/mobile-ci.yml` never triggered due to a path-prefix
  mismatch (see File Changes) — CI had silently never run.
- 2026-08-08: Two files had import paths that would have broken at runtime after the
  `src/` rename (`cloud_functions/voice_analysis/main.py`,
  `legacy_flask_gateway/core/*.py`) — fixed as part of the same change, not left broken.

## Known Issues

(Carried forward from `docs/archive/PROJECT_STATUS.md`/`TECHNICAL_INVENTORY.md`,
reconfirmed 2026-08-08 — see [ARCHITECTURE.md#known-gaps](ARCHITECTURE.md#known-gaps)
and [SECURITY.md](SECURITY.md#known-limitations--recommendations) for full detail.)

- Weapon/voice detection in `cloud_functions/` fall back to synthetic models in places.
- `/api/v1/alerts/live` state is in-process, not persisted — resets on restart, won't
  scale across replicas.
- `ml_training/`'s training pipeline isn't reproducible from a clean clone (dataset not
  committed).
- No firmware for the mobile UI's "smart ring"/"pendant" devices.
- Most `mobile/` screens are still mock-backed.
- No rate limiting or refresh-token revocation on the backend.
- **The Supabase secret key formerly in `deployment/docker/.env` was live on
  `origin/main` since the repo's first commit and needs manual rotation** — untracking
  the file (done 2026-08-08) does not itself invalidate the key.
- `make setup`/`make train`/`make test` reference scripts that don't exist in
  `scripts/`.
- `requirements.txt` has a duplicate `alembic` entry and mixes three unrelated
  dependency sets (backend / legacy gateway / ML training) in one file.

## Pending Tasks

- Rotate the Supabase secret key (user action, cannot be done by an automated pass).
- Decide whether `legacy_flask_gateway/` should eventually be deleted outright once
  feature parity with `fastapi_app/` is explicitly confirmed route-by-route.
- Split `requirements.txt` by concern (backend / legacy / ML training).
- Add a backend CI workflow — none exists today; only mobile has one.
- Finish `mobile/`'s real-API integration (Phase 4 of its build sequence).
- Add real screenshots to `README.md`'s Screenshots section.

## Future Improvements

See README.md's "Future Improvements" section — kept in one place to avoid drift
between this file and the README.

## Technical Debt

- Duplicated MQTT client implementations (`paho-mqtt` in the legacy gateway,
  `asyncio-mqtt` in `fastapi_app/`) — collapse to one once the legacy gateway's fate is
  decided.
- `deployment/config/nginx.conf` and `prometheus.yml` describe a microservices
  topology the current `docker-compose.yml` explicitly removed — either delete them or
  clearly mark them as reference-only for a future scale-out.
- Two Python test files (`test_authentication.py`, `test_microservices.py`) test an
  architecture that no longer exists (standalone services on ports 8001–8004) — decide
  whether to update or remove them.

## AI Notes

This file and the surrounding documentation set were produced by an AI-assisted audit
on 2026-08-08, covering the full monorepo (scope confirmed explicitly with the project
owner before proceeding, since the initial request's assumption of a single cohesive
project didn't match the repo's actual shape as two backends + a frontend + ML/hardware/
deployment code). Every claim in this documentation set was derived from direct
inspection of the current source — router files, schemas, models, config, `pubspec.yaml`,
`requirements.txt`, git history — not from the pre-existing (and partly fabricated)
documentation, which is preserved in `docs/archive/` for historical context only.
Facts here should be re-verified against the code before being treated as ground truth
in future work — this file describes state as of 2026-08-08, not necessarily today.

## Last Updated

2026-08-08

## Change History

- **2026-08-08** — Initial creation of this file as part of a full-repo audit: git
  hygiene cleanup (leaked secret untracked, chrome profile / db files / pycache
  untracked, one duplicate firmware file and one dead script removed), legacy backend
  and ML training code relocated for clarity, a broken CI workflow fixed, and the full
  documentation set (this file plus 9 others) written from scratch against current
  source. See [CHANGELOG.md](CHANGELOG.md) for the itemized diff.
