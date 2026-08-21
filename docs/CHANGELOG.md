# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning
follows [Semantic Versioning](https://semver.org/). This project has not cut a formal
release yet — entries below are grouped by notable milestones instead of version tags
until the first tagged release.

## [Unreleased]

### 2026-08-15 — Firebase auth, design system, repo cleanup

#### Added
- iOS Firebase configuration: `GoogleService-Info.plist`, referenced from the
  Xcode Resources build phase, with `REVERSED_CLIENT_ID` registered as a URL
  scheme for `google_sign_in`. Not verified by an iOS build (Windows host).
- Guest sign-in (Firebase Anonymous) — "Continue as guest" reaches the SOS button
  without an account. The backend still provisions a real account keyed to the
  Firebase uid.
- `AuthRepositoryNative` — email/password auth served directly by `fastapi_app`,
  selectable with `--dart-define=USE_FIREBASE_AUTH=false`. Needs no Firebase console
  configuration.
- SRS section 4.1 auth: emailed OTP verification (FR-AUTH-01), password change with
  cross-device session revocation (FR-AUTH-06), 5-failure/15-minute lockout
  (FR-AUTH-07), 30-day deletion grace with an hourly purge worker (FR-AUTH-08),
  and password reset by OTP.
- `SaAmbientBackground` — a global aurora layer giving the glassmorphism in SRS
  section 1 something to refract.
- 51 new tests: `test_auth_security.py` (27), `test_firebase_token_verification.py`
  (8), `auth_repository_native_test.dart` (16).

#### Fixed
- **Alembic could never run.** `alembic/env.py` drove an async URL with a sync
  engine (`MissingGreenlet`), and `alembic/script.py.mako` was missing so no
  migration could be generated. The dev database had been built by `create_all`
  with no `alembic_version` row and six unapplied migrations.
- **Firebase tokens rejected on clock skew.** A machine a second behind Google saw
  fresh tokens fail as "Token used too early" — intermittent, unreproducible
  sign-in failures. Now tolerates 30s.
- **Response headers were silently dropped.** The global `HTTPException` handler
  discarded `exc.headers`, killing `Retry-After` on lockouts and
  `WWW-Authenticate` on 401s across every endpoint.
- Phone and anonymous accounts were all filed under `@phone.safeherapp.com`; the
  synthetic address is now provider-aware.
- Token lifetimes corrected to 15 minutes / 30 days per FR-AUTH-04 (were 30 min / 7 days).
- Light mode: login and forgot-password forced a dark background and used hardcoded
  white text, failing the 4.5:1 contrast floor in SRS 5.4. Shadows were neutral
  black where SRS section 2.4 specifies violet.

#### Changed
- Android: `com.google.gms.google-services` 4.3.15 → 4.5.0; removed the
  `com.google.firebase.crashlytics` Gradle plugin, which was applied without
  `firebase_crashlytics` ever being in pubspec.yaml.

#### Removed
- `legacy_flask_gateway/` — the superseded Flask backend. Nothing outside itself
  imported it. `flask`, `flask-cors` and `paho-mqtt` were **kept** because
  `deployment/docker/safeher_event_processor.py` imports them; `flask-sock` was
  dropped as genuinely unused.
- `mobile/deprecated/legacy_flutter_tree/` (134 files) — an older Flutter tree,
  unreferenced by `mobile/lib` or `mobile/test`.
- `mobile/.chrome_fresh_profile/` (3,152 files, ~400 MB) — a committed Chrome
  profile. The 2026-08-08 entry below claims this was untracked, but `git ls-files`
  still listed every file, so that cleanup never actually landed.
- `tests/test_microservices.py` (8/8 skipped; targets ports 8001-8004 that no longer
  exist) and `tests/test_authentication.py` (undefined `token` fixture).
- Empty root `lib/` and `test/` directory skeletons; all tracked `__pycache__` and
  `*.db` files (`safeher.db` and `test_safeher.db` kept on disk as live dev data).
- Working tree: 389 MB → 103 MB.


### Added
- Full documentation set: `README.md`, `ARCHITECTURE.md`, `API.md`, `SETUP.md`,
  `CONTRIBUTING.md`, `DEPENDENCIES.md`, `PROJECT_STRUCTURE.md`, `SECURITY.md`,
  `MEMORY.md` (this file's companion).
- `docs/archive/` — every pre-audit doc preserved for historical reference.

### Changed
- Renamed `src/models/` → `ml_training/` and `src/` (remaining Flask gateway code) →
  `legacy_flask_gateway/` for clarity; updated the two files with hardcoded `src/...`
  paths (`cloud_functions/voice_analysis/main.py`, `validate_dataset.py`) and the two
  internal absolute imports in the relocated gateway code.
- Fixed `.github/workflows/mobile-ci.yml`: its path filters and working directory
  referenced `SafeHer/mobile/**`, which never matched real paths in this repo (the
  repo root already is `SafeHer`) — the workflow had never actually triggered.
  Corrected to `mobile/**`, and broadened `flutter analyze lib/main.dart lib/app` (a
  nonexistent path) to a plain `flutter analyze`.

### Removed
- `audit_system.py` — dead script auditing the (now-archived) legacy Flask gateway,
  referenced by nothing else in the repo.
- `hardware/esp32_cam/smart_glasses.ino` — byte-identical duplicate of
  `hardware/smart_glasses/smart_glasses.ino`.
- `deployment/docker/dy` — a stray cached HTTP error response, not source code.

### Fixed / Security
- Removed `deployment/docker/.env` (containing live Supabase keys) from git tracking.
  **The key must still be rotated manually** — it was present on `origin/main` since
  the repo's first commit and must be treated as compromised regardless of the
  untrack. See [SECURITY.md](SECURITY.md).
- Untracked `mobile/.chrome_fresh_profile/` (an accidentally-committed Chrome browser
  <!-- NOTE 2026-08-15: this untracking never landed; the files were still in the
  index and were removed for real on 2026-08-15. -->
  profile, ~3,150 files), all `__pycache__/` directories, and the four root-level
  `.db` files (`safeher.db`, `safeher.runtime.db`, `safeher_app.db`,
  `test_safeher.db`) — none of these should be version-controlled. `.gitignore`
  expanded to prevent recurrence.

## Prior history (untagged)

Reconstructed from commit history and the archived reports in `docs/archive/` for
context — not exhaustive:

- **2026-04-19** — Real API integration layer, offline queue (Hive-backed retry +
  connectivity awareness), accessibility/performance audit pass on `mobile/`.
- **2026-04-03** — FastAPI backend (`fastapi_app/`) introduced alongside the existing
  Flask gateway; `app.py` becomes the primary backend entrypoint.
- **2026-03-23 to 2026-03-30** — Original Flask-based event-processor architecture,
  ML training pipeline (motion/voice/weapon detection), ESP32 firmware, Docker Compose
  deployment, and the first project audit reports (now in `docs/archive/`).
- **2026-02-08** — Repository initialized, MIT license added.

## [0.1.0] — baseline

The state of the project immediately before the 2026-08-08 audit: a working FastAPI
backend, an in-progress Flutter mobile app (mock-backed, Phases 0–6 of its own build
sequence complete through Home + offline queue + accessibility audit), ESP32 firmware
for two devices, four ML inference cloud functions, and a Docker Compose deployment —
alongside an unused legacy Flask backend and several git-hygiene issues addressed in
[Unreleased](#unreleased) above.
