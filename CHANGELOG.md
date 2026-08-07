# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning
follows [Semantic Versioning](https://semver.org/). This project has not cut a formal
release yet — entries below are grouped by notable milestones instead of version tags
until the first tagged release.

## [Unreleased]

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
