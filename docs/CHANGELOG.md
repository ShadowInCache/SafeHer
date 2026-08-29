# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning
follows [Semantic Versioning](https://semver.org/). This project has not cut a formal
release yet — entries below are grouped by notable milestones instead of version tags
until the first tagged release.

## [Unreleased]

### 2026-08-30 — security audit: one real hole, and two boundaries nobody was watching

#### Fixed
- **Unthrottled outbound email to an arbitrary address.**
  `POST /users/me/emergency-contacts/{id}/verify/send` sends a code to an
  address the caller chose and had no rate limit, while every other
  mail-sending route had one — the action sits past a path parameter and no
  prefix rule reached it. An account could add any address as a "contact" and
  loop the endpoint to bomb that inbox from SafeHer's verified sender. Capped
  at 12/hour. `RateLimitRule` gained an optional `suffix` so a rule can target
  an action past a path parameter without throttling its neighbours.
- **A provider exception was returned to the caller.** The same route answered
  `Could not send the code: {exc}`, handing the upstream error body — and
  whatever hostnames or configuration detail it carried — to any authenticated
  client. Logged server-side now, with a generic message to the user. It was
  the only instance of that pattern in the codebase.

#### Added
- `tests/test_realtime_and_device_isolation.py` — cross-account tests for the
  two id-bearing routes that had none: the live alert WebSocket
  (`WS /ws/alerts/{user_id}`, which had no test anywhere) and
  `POST /devices/{id}/heartbeat`. Both were already correctly guarded; neither
  was proven. The WebSocket tests speak the ASGI protocol directly, because
  Starlette's `TestClient` is incompatible with the installed httpx.
- `TestRouteRegistry` — every id-bearing route must be classified as
  owner-checked or token-credential, and the suite fails when a new one
  appears unclassified or an entry goes stale. The two gaps above existed
  because nothing noticed them; this makes the absence itself fail.
- `tests/test_outbound_email_abuse.py` — pins the new limit and, as
  importantly, pins that it did not spread to reading or editing contacts.

#### Verified, not changed
Authorization was audited across all 22 id-bearing routes and found correct
everywhere: ownership is re-derived from the token, and missing and not-yours
both return 404. Tokens are held in `FlutterSecureStorage`, not Hive. Evidence
is AES-256-GCM sealed before any backend sees a byte, retrieval is
ownership-checked and streamed, and no public URL is ever issued. Uploads are
MIME allow-listed and size-capped. The unhandled-exception handler returns a
generic 500. No secrets are tracked in the repository.

428 backend tests passing (was 409), 7 skipped, no regressions.


### 2026-08-29 — the glove detects with the phone in a pocket

#### Added
- **Background detection.** `mobile/lib/core/background/safety_foreground_service.dart`
  runs a `connectedDevice|location` foreground service (via
  `flutter_foreground_task`) for exactly as long as a glove is connected, so
  Android stops freezing the process and the BLE notifications keep arriving.
- `GloveAutoTrigger` (`mobile/lib/features/safety/data/glove_auto_trigger.dart`)
  — the glove's vote, moved out of a widget and into a `keepAlive` provider.
- `DetectionSources.backgroundWatchActive` — reports whether the service is
  *genuinely* running, so the UI only claims the pocket case works when the
  platform confirms it started.
- A background alarm path: the countdown is routed to first and the screen
  woken second, so it is already up when the activity comes forward.
- 34 tests, including the glove vote driven entirely without a widget tree, and
  the BLE wire contract asserted against the firmware's literal payloads.
- `glove/README.md` and a rewritten `mobile/README.md`.

#### Fixed
- **Automatic detection was silently conditional on the app being looked at.**
  The glove's vote ran inside `SafetyTriggerListener.build()`, and Flutter stops
  pumping frames when the app leaves the screen — so a pocketed phone, the case
  the glove exists for, raised nothing. A foreground service alone would not
  have fixed this: the process would have been alive with nothing reading the
  stream.
- **The device card claimed a heart rate of zero.** The firmware sends `0` for
  bpm and battery to avoid fabricating sensor data, but a literal `0` parses as
  a measurement. Both now read as absent — no wearer has a heart rate of zero,
  and no glove transmitting over BLE has a flat battery. `accelG` and `gyroDps`
  keep zero as a real reading.
- `ref.read` during provider disposal threw; the service handle is resolved in
  `build` and held.
- `dart:io` in a web-reachable library broke the web build, caught by the repo's
  own guard test. Replaced with `defaultTargetPlatform`.

#### Changed
- Android manifest gains `FOREGROUND_SERVICE_CONNECTED_DEVICE` and the
  `<service>` declaration. Release APK 70.7 MB → 71.5 MB.
- Documentation rewritten against current source: `README.md`,
  `docs/PROJECT_STRUCTURE.md`, `docs/ARCHITECTURE.md`, `docs/TRACEABILITY.md`,
  `docs/SRS_STATUS.md`. Test counts were three sessions stale (639 → 747 mobile,
  342 → 409 backend) and `glove/` was absent from every structural document.


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
