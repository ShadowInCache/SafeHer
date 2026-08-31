# Project Memory

This file is the project's long-term memory. Every future modification of consequence
— adding/deleting files, refactoring, renaming, moving folders, dependency changes,
bug fixes — should append an entry under **Change History**, in chronological order.
Never overwrite or delete a prior entry.

## Project Overview

SafeHer is an AI-powered wearable safety platform for women. The repo is a monorepo
containing a current FastAPI backend (`fastapi_app/`), a Flutter mobile app
(`mobile/`), ESP32 device firmware (`hardware/`), an ML training pipeline
(`ml_training/`), serverless inference functions (`cloud_functions/`), and a Docker
Compose deployment (`deployment/`). See [ARCHITECTURE.md](ARCHITECTURE.md) for how the pieces
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
  (`supabase_setup.sql`) is a parallel, append-only archive. Written by
  `deployment/docker/safeher_event_processor.py` **only**, over plain REST.
  `fastapi_app` has no Supabase settings and no client — the `supabase`
  package was in both requirements files and imported by nothing, and was
  removed on 2026-08-17.

- **Firebase Auth is the credential collector; `fastapi_app` owns the account**
  (2026-08-14). Every Firebase sign-in is exchanged for a backend JWT at
  `POST /api/v1/auth/firebase/exchange`, which auto-provisions the user. Firestore
  is *not* used despite SRS section 8 describing a Firestore schema -- the
  transactional store is SQLAlchemy (SQLite in dev, Postgres/Supabase in prod), and
  the SRS's collection shapes are realised as relational tables.
- **Two interchangeable auth backends** (2026-08-14). `AppConfig.useFirebaseAuth`
  (default `true`) selects `AuthRepositoryRemote` (Firebase + exchange);
  `--dart-define=USE_FIREBASE_AUTH=false` selects `AuthRepositoryNative`, which
  talks to `fastapi_app` directly and needs no Firebase console configuration. The
  native path cannot do Google, Apple or guest sign-in, which require a real
  identity provider.
- **Migrations are the single source of schema truth** (2026-08-14). `init_db()`
  runs `alembic upgrade head` on startup instead of `Base.metadata.create_all`.
  A database built by the old `create_all` path is adopted automatically: startup
  stamps it at head, then upgrades. `create_all` is deliberately not used -- it
  silently diverges from the migration chain, which is how the dev database ended
  up with no `alembic_version` row and six unapplied migrations.
- **Email verification is enforced only when it is deliverable** (2026-08-14).
  `require_email_verification` defaults to "on iff SMTP is configured". Forcing it
  on without a mail server would create accounts that can never sign in.
- **The ambient aurora is a global layer, not per-screen** (2026-08-15).
  `SaAmbientBackground` is mounted once in `MaterialApp.builder`; every `Scaffold`
  is transparent. It is static by design -- it sits above the router, so an
  animated field would never settle for `pumpAndSettle` and would make all ~200
  golden tests flaky.

## Folder Changes

- 2026-08-08: `src/models/` → `ml_training/` (top-level rename, no code changes beyond
  path references).
- 2026-08-08: `src/` (remaining: `core/`, `services/`, `utils/`) → `legacy_flask_gateway/`.
- 2026-08-08: `docs/*.md` (8 pre-existing reports) + root `README.md` + `QUICKSTART.py`
  → `docs/archive/`, preserved verbatim (`QUICKSTART.py` renamed to
  `QUICKSTART.py.txt` since it's no longer meant to be executed).

- 2026-08-15: `legacy_flask_gateway/` — **deleted**. The 2026-08-08 audit
  relocated it pending a route-by-route parity check; nothing outside itself ever
  imported it (verified by repo-wide grep), so it was removed rather than carried
  further. Recoverable from git history.
- 2026-08-15: `mobile/deprecated/legacy_flutter_tree/` — **deleted** (134 tracked
  files). An older Flutter app tree, unreferenced by `mobile/lib` or `mobile/test`.
- 2026-08-15: `mobile/.chrome_fresh_profile/` — **deleted** (3,152 tracked files,
  ~400 MB). An accidentally-committed Chrome browser profile.
- 2026-08-15: root `lib/` and `test/` — **deleted**. Empty directory skeletons
  containing zero files.
- 2026-08-15: `fastapi_app/workers/` — **added**, holding `deletion_purge.py`.

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

- 2026-08-14: `alembic/env.py` — rewritten for async engines. It previously built
  an async URL (`+aiosqlite`/`+asyncpg`) and drove it with a **sync**
  `engine_from_config`, which fails at connect time with `MissingGreenlet`. Together
  with a missing `alembic/script.py.mako`, this meant migrations had never been
  runnable and `revision --autogenerate` could not write a file at all.
- 2026-08-14: `alembic/script.py.mako` — **restored**; it was absent, so no new
  migration could be generated.
- 2026-08-14: `fastapi_app/db.py` — added `sync_database_url()`, translated
  Supabase's libpq-style `?sslmode=require` into the `ssl` argument asyncpg
  accepts, and replaced `create_all` with migration-driven `init_db()`.
- 2026-08-14: `fastapi_app/main.py` — the custom `HTTPException` handler dropped
  `exc.headers`, silently discarding `Retry-After` on lockout responses and
  `WWW-Authenticate` on 401s across every endpoint. Now forwarded.
- 2026-08-15: `fastapi_app/services/firebase_auth.py` — added
  `CLOCK_SKEW_TOLERANCE_SECONDS` (30s). Firebase mints tokens against Google's
  clock; a machine a second behind saw fresh tokens rejected as "Token used too
  early", presenting as intermittent, unreproducible sign-in failures. Also logs
  the rejection reason (previously swallowed entirely) while still returning a
  generic 401, and derives synthetic addresses per provider
  (`@anonymous.safeherapp.com` / `@phone.safeherapp.com`) instead of labelling
  every emailless account as a phone user.
- 2026-08-15: `mobile/lib/core/theme/app_shadows.dart` — light mode used neutral
  black shadows; SRS section 2.4 specifies violet for every level with no
  per-brightness split. This was the main reason light mode read as generic
  Material grey.
- 2026-08-15: `mobile/lib/features/auth/presentation/login_screen.dart` and
  `forgot_password_screen.dart` — stopped forcing `AppColors.dark900`, and replaced
  hardcoded `Colors.white` text/icons that were invisible against a light
  background (SRS 5.4 requires 4.5:1).

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

- 2026-08-15: `tests/test_microservices.py` — all 8 tests skipped
  unconditionally ("Motion service not running"); it targets standalone services on
  ports 8001-8004 that no longer exist.
- 2026-08-15: `tests/test_authentication.py` — a test referenced a `token` fixture
  that was never defined (collection error). Superseded by
  `tests/test_auth_security.py`.
- 2026-08-15: Untracked **and this time actually removed** — the 2026-08-08 entry
  below records untracking `mobile/.chrome_fresh_profile/`, the `*.db` files and
  all `__pycache__/`, but `git ls-files` still listed 3,152 + 46 of them, so that
  cleanup never landed. Re-done: `git rm --cached` on all of them, `safeher.db` and
  `test_safeher.db` kept on disk as live dev data. Repo working tree went from
  389 MB to 103 MB.

## Added Files

- 2026-08-08: Full documentation set — `README.md`, `ARCHITECTURE.md`, `API.md`,
  `SETUP.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `DEPENDENCIES.md`,
  `PROJECT_STRUCTURE.md`, `SECURITY.md`, `MEMORY.md` (this file). `docs/archive/README.md`
  explaining the archive's contents.

- 2026-08-14/15: Backend — `fastapi_app/repositories/auth_security.py`,
  `fastapi_app/services/email.py` (real SMTP; no pretend-send mode),
  `fastapi_app/workers/deletion_purge.py`, `alembic/versions/0007_auth_hardening.py`,
  `tests/test_auth_security.py` (27 tests), `tests/test_firebase_token_verification.py`
  (8 tests).
- 2026-08-14/15: Mobile — `lib/features/auth/data/auth_repository_native.dart`,
  `lib/shared/components/layout/sa_ambient_background.dart`,
  `test/features/auth/data/auth_repository_native_test.dart` (16 tests).

- 2026-08-15: `mobile/ios/Runner/GoogleService-Info.plist` — iOS Firebase config
  for `safeher-2a1f2`, bundle id `com.example.safeherApp`. Wired into
  `Runner.xcodeproj/project.pbxproj` (Resources build phase) and its
  `REVERSED_CLIENT_ID` registered as a URL scheme in `Info.plist`. Not verified by
  an iOS build — Flutter cannot build for iOS on Windows.

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

2026-08-15

## Change History

- **2026-08-08** — Initial creation of this file as part of a full-repo audit: git
  hygiene cleanup (leaked secret untracked, chrome profile / db files / pycache
  untracked, one duplicate firmware file and one dead script removed), legacy backend
  and ML training code relocated for clarity, a broken CI workflow fixed, and the full
  documentation set (this file plus 9 others) written from scratch against current
  source. See [CHANGELOG.md](CHANGELOG.md) for the itemized diff.

- **2026-08-14** — Backend auth brought up to SRS section 4.1: emailed OTP
  verification (FR-AUTH-01), 15-minute/30-day token lifetimes (FR-AUTH-04),
  password change with cross-device session revocation (FR-AUTH-06), 5-failure
  15-minute lockout (FR-AUTH-07), and 30-day deletion grace with an hourly purge
  worker (FR-AUTH-08). Fixed three latent bugs found on the way: Alembic could
  never run (async URL on a sync engine, plus a missing script template), the
  schema was `create_all`-built with no `alembic_version`, and the global
  exception handler discarded response headers. Added `AuthRepositoryNative` so
  account creation no longer depends on Firebase console configuration.
- **2026-08-15** — Firebase Authentication enabled by the project owner (Google,
  Phone, Anonymous, Email/Password); app default flipped to the Firebase path and
  guest sign-in added. Fixed a clock-skew token rejection that would have caused
  intermittent production sign-in failures. Frontend: global aurora ambient layer,
  translucent surfaces, SRS-compliant violet shadows in both themes, and light-mode
  contrast fixes. Repo cleanup: deleted the legacy Flask gateway, the deprecated
  Flutter tree, a committed 400 MB Chrome profile, empty root `lib/`+`test/`
  skeletons and two dead test files; genuinely untracked the artifacts the
  2026-08-08 pass had only claimed to untrack. Working tree 389 MB → 103 MB.
- **2026-08-15 (later)** — iOS Firebase configuration added. Unlike the Android
  file, the plist carries a real `CLIENT_ID`/`REVERSED_CLIENT_ID`, so iOS Google
  sign-in needs no separate fingerprint registration. Two steps that are easy to
  miss were done alongside it: referencing the plist from `project.pbxproj` (a
  file merely present in `ios/Runner/` is never copied into the bundle) and
  registering the reversed client id as a URL scheme (`google_sign_in`'s OAuth
  callback needs it). Neither is verifiable on Windows.

- **2026-08-15 (later still)** — SRS SCREEN 9 (Dashboard, `/dashboard`) built, the
  last SRS screen that did not exist. A prior pass had folded analytics into Home
  and removed the Dashboard nav tab; the SRS specifies both, so the screen was
  built and the bottom navigation restored to the specified four tabs
  (Home/Monitor/Dashboard/Profile), moving Device Management off the bar it was
  never specified onto. New backend endpoint `GET /api/v1/dashboard/analytics` and a
  new `SaHeatGrid` component. Two real defects surfaced while testing: an
  `IntrinsicHeight` wrapping cards that contain a `LayoutBuilder` throws during
  layout (a production crash, not just a test failure), and a stagger built on
  `Future.delayed` leaks a timer when its card scrolls out of a lazily-built
  sliver. Coverage was measured for the first time: **75.2%**, above the SRS's 70%
  gate. Also added [docs/SRS_STATUS.md](SRS_STATUS.md), the per-session SRS
  compliance report, and removed the empty `legacy_flask_gateway/` directory tree
  the 2026-08-08 untracking pass left behind on disk.

- **2026-08-21** — Root-level declutter. Ten documents moved from the repo root into
  `docs/` (`API.md`, `ARCHITECTURE.md`, `CHANGELOG.md`, `CONTRIBUTING.md`,
  `DEPENDENCIES.md`, this file, `PROJECT_STRUCTURE.md`, `SECURITY.md`, `SETUP.md`,
  `SRS.md`), leaving only `README.md` and `LICENSE` as documentation at the top level.
  `validate_dataset.py` moved to `scripts/`; `supabase_setup.sql` moved to
  `deployment/sql/`. Deleted `xgboost_motion_model.json` and
  `motion_training_results.json` from the root — they were **stale copies with
  different content** from the `ml_training/motion_detection/` versions the trainer
  actually writes, and a grep confirmed nothing loaded them; the cloud function reads
  `cloud_functions/motion_detection/models/`, a directory that does not exist. Also
  removed `mobile/flutter_err.txt` and `mobile/flutter_out.txt`, two captured
  `flutter run` logs committed by accident, and added `.gitignore` rules for those and
  for JVM `hs_err_pid*.log` crash dumps so the next redirect does not follow them in.
  Five references were rewired: `tests/test_traceability.py` reads `docs/SRS.md`
  (the only hard failure — it is enforced by a test), `README.md` links gained a
  `docs/` prefix, and `docs/SRS_STATUS.md`, `docs/TRACEABILITY.md` and this file now
  link to siblings rather than parents. A link checker verified all 49 relative
  markdown links resolve.

  **No code directory moved, deliberately.** `fastapi_app/`, `mobile/`, `alembic/` and
  `tests/` stay where they are: `fastapi_app.main:app` is the import path the Render
  deployment, `Dockerfile.processor`, the `Makefile`, `alembic.ini` and every test
  depend on. A `backend/` folder or an `apps/`-style monorepo was considered and
  rejected — it would trade a tidier tree for a broken production deploy, and the tree
  was never what made this repo hard to work in.

- **2026-08-29** — Glove detection made real off screen, and the docs brought back
  in line with the code. Three things were wrong at once and only one was obvious.
  The glove's vote ran in `SafetyTriggerListener.build()`, so it stopped the moment
  the app left the screen — automatic detection was quietly conditional on being
  looked at, which is the inverse of what the glove is for. It moved to
  `GloveAutoTrigger`, a `keepAlive` provider driven by `ref.listen`, whose tests run
  against a bare `ProviderContainer` so a regression back into a widget fails the
  suite. Android froze the process independently of that, so
  `core/background/safety_foreground_service.dart` runs a
  `connectedDevice|location` foreground service while a glove is connected. And
  because starting that service can be refused, `DetectionSources` gained
  `backgroundWatchActive` and reports the platform's answer rather than the app's
  intention — the fourth time a control here would have looked like protection while
  governing nothing.

  Separately, `b0e1813` (Akhilesh) added the firmware's telemetry characteristic.
  Its UUID and field order match the app exactly, but `sendTelemetry` sends `0` for
  heart rate and battery to *avoid* fabricating data, and a literal zero parses as a
  measurement — the device card rendered "0 bpm". The app now reads a zero heart rate
  and a zero battery as absent, keeping zero as a real value for accel and gyro.
  The firmware fix is still open and needs no app change when it lands.

  Two defects were found by tests already in the repo rather than by review:
  `ref.read` throws once disposal has begun, and `dart:io` is banned in any
  web-reachable library under `lib/`.

  Documentation was rewritten against current source in the same pass.
  `mobile/README.md` described `lib/app/core`, an `integration_test/` directory and
  four `--dart-define` names, **none of which exist** — it had been describing a
  different app for some time. `docs/PROJECT_STRUCTURE.md` had no `glove/` entry at
  all and still cited a 67-test backend suite. Counts across `README.md` were three
  sessions stale. New: `glove/README.md`, covering the firmware, the dataset, the
  collect → train → convert pipeline and the two path traps in it.

- **2026-09-01** — First detection model trained end to end. A YOLOv8n weapon
  detector (pistol, knife) reached mAP@0.5 0.907 and recall 0.835 on a held-out
  split, from 7,539 images pulled together out of Open Images V7,
  OD-WeaponDetection and Sohas. Quantised to 3.36 MB and bundled at
  `mobile/assets/models/`.

  The interesting part was the second training run. v1 detected knives much
  worse than pistols, and the instinct is to blame resolution — knives are thin
  and small. The measurement said otherwise: knife recall was *flat* across box
  sizes and worse than pistol even on large boxes, meaning a knife filling the
  frame was still missed one time in six. That is intra-class variance, not
  scale. The cause turned out to be a data-collection mistake: Open Images
  treats `Knife`, `Kitchen knife` and `Dagger` as three separate boxable
  classes, and the first download asked only for `Knife`. Adding the other two
  took knife recall from 0.763 to 0.827 and closed the pistol/knife gap from
  6.7 points to 1.6.

  Two methodological points worth carrying forward. The test split was kept
  byte-identical between runs — had new data been spread across all three
  splits, "knife AP went up" would have been unfalsifiable. And every candidate
  image was content-hashed against all three existing splits, which caught
  3,541 duplicates out of 4,511, since Sohas overlaps Granada's other folders
  heavily; without that check images already in `test` would have landed in
  `train` and inflated the exact metric under investigation.

  Also settled: the model cannot run on the glasses and never could. An
  ESP32-CAM is two orders of magnitude short on memory and compute, and
  compression does not touch the part that breaks — activation memory. The
  glove is not a counterexample; a tree ensemble over 51 scalar features is a
  different kind of workload from a convnet over 409,600 pixels. Inference runs
  on the phone; the glasses capture and transmit. Recorded in
  `docs/WEAPON_INFERENCE_PLACEMENT.md`.

  Nothing loads the model yet — no runtime dependency, no inference code,
  `weapon_score` still has no producer. Bundling a model and having a detector
  are different things and the docs now say so.
