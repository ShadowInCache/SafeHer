# Contributing

## Coding standards

**Backend (`fastapi_app/`)**
- Routers stay thin: request validation lives in `schemas.py`, DB access in
  `repositories/`, business logic in `services/`. Don't put SQLAlchemy queries
  directly in a router function — follow the pattern in `routers/devices.py`.
- Every new table needs an Alembic migration (`alembic revision --autogenerate -m "..."`)
  committed alongside the `models.py` change — don't hand-edit the schema.
- New settings go in `fastapi_app/config.py`'s `Settings` class with a sane default,
  and get documented in [SETUP.md](SETUP.md#2-environment-variables).

**Mobile (`mobile/`)** — this codebase follows a stricter set of rules than most
Flutter projects, established from its original build spec:
- State management is Riverpod only — no `setState`.
- Navigation is GoRouter only — no direct `Navigator.push`.
- Icons are custom vector widgets (`SaIcon`) via `CustomPainter` — no Material default
  icons.
- No placeholder screens or `TODO` widgets committed — a screen isn't done until it
  has a widget test and a golden test.
- Each `features/<name>/` follows `data/` → `domain/` → `presentation/`. Put mock
  repositories behind the same interface the real one will implement, gated by
  `AppFlavor.isMock`.

**Both**
- Match existing formatting (`dart format` for mobile, standard PEP 8 for Python — no
  enforced formatter is currently configured for the backend; keep diffs minimal and
  consistent with surrounding code).
- Don't introduce a new dependency for something 10 lines of code can do — see
  [DEPENDENCIES.md](DEPENDENCIES.md) before adding a package.

## Guard tests you should know about before they fail on you

Four tests police things a reviewer reliably misses. None of them is about the
feature you are writing, and all of them fail the suite.

- **`tests/test_traceability.py`** — every requirement in `docs/SRS.md` needs a
  row in `docs/TRACEABILITY.md`, every backticked path in that row must exist,
  and a row marked *not built* may not cite an implementation. Renaming a file a
  requirement points at breaks this, which is the point.
- **`mobile/test/features/devices/data/ble_service_platform_test.dart`** —
  `dart:io` is banned in any web-reachable library under `mobile/lib/`. It throws
  in a browser and shows up in no VM test. Ask platform questions of
  `defaultTargetPlatform` / `kIsWeb`, or use a conditional import with an
  `_io.dart` half.
- **`mobile/test/features/devices/domain/glove_protocol_test.dart`** — the BLE
  wire format is asserted against the firmware's literal payloads, including the
  class list in `CLASS_NAMES` order. The firmware indexes that array to pick a
  label, so reordering it would deliver a fall to the app under another word.
- **`tests/test_health_endpoints.py`** — `/health` must stay constant-time. It is
  what uptime monitoring points at, and a cold call to `/status` once timed out
  at 40 seconds.

## One rule that is not a test

**Before adding any safety setting, check what reads it.** Four times now this
codebase has shipped a control that looked like protection while governing
nothing: the threat-threshold slider, the biometric toggle, the detection status,
and very nearly the background-detection claim. Each was found later, by someone
reading the code rather than using the app.

A control that does nothing is worse on a safety product than no control at all,
because it is indistinguishable from one that works. Where a capability can fail
at runtime — a permission denied, a service the OS refuses to start — report the
platform's answer, not your intention to have asked.

## Branch strategy

The project has been developed as a single contributor committing directly to `main`
with descriptive, phase-labeled commits (see `git log`). As more people contribute,
move to:
- `main` stays deployable at all times.
- Feature work happens on `<type>/<short-description>` branches (e.g.
  `feat/emergency-contacts-sync`, `fix/websocket-reconnect`), merged via PR.
- Rebase on `main` before opening a PR; avoid merge commits in feature branches.

## Commit message guidelines

Existing history uses short, imperative, present-tense subject lines — keep doing
that:
```
Fix Monitor screen blank/crash bug and missing bottom nav
Add missing entry point to the Search screen
Phase 5: offline queue (Hive-backed retry queue + ConnectivityNotifier)
```
- Subject line: what changed, imperative mood, no trailing period, ~70 chars.
- Body (optional): why, not what — the diff already shows what.
- Reference the affected area when it's not obvious from context (`mobile:`,
  `fastapi_app:`, `ml_training:`).

## Pull request process

1. Keep PRs scoped to one concern — one screen, one endpoint, one bug fix. This repo's
   own commit history (one phase/feature per commit) is the model to follow.
2. Before opening: `pytest tests/` (backend) and/or `flutter analyze && flutter test`
   (mobile), whichever your change touches.
3. Describe *why*, not just *what* — link the issue or describe the user-facing
   symptom being fixed.
4. If your change touches the database schema, the API contract (`API.md`), or adds/
   removes a dependency, update the relevant doc in the same PR — see the folder
   conventions below.

## Folder conventions

- New backend endpoint → add to the appropriate `fastapi_app/routers/*.py`, add its
  schema to `schemas.py`, document it in [API.md](API.md).
- New mobile screen → new folder under `mobile/lib/features/<name>/` with
  `data/domain/presentation`, route registered in `mobile/lib/core/router/`, mirrored
  test folder under `mobile/test/features/<name>/`.
- New ML model → new folder under `ml_training/<model_name>/`, corresponding inference
  function under `cloud_functions/<model_name>/` if it needs to run standalone.
- New firmware → new folder under `hardware/<device_name>/`.

## Security-sensitive changes

Anything touching auth, secrets, or `.env`-adjacent config: read
[SECURITY.md](SECURITY.md) first. Never commit a populated `.env` file, under any
directory — `deployment/docker/.env` was committed with real Supabase secrets before
the 2026-08-08 audit; don't repeat that.
