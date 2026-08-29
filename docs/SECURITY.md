# Security

## Reporting a vulnerability

This is currently a single-maintainer project with no formal disclosure program. If
you find a vulnerability, open a private report to the maintainer rather than a public
issue.

## Secrets handling

- **Never commit a populated `.env` file, anywhere in the repo.** The root
  `.gitignore` covers `.env` / `.env.*` (with `.env.example` explicitly allowed
  through). `deployment/docker/` needs the same discipline — a populated
  `deployment/docker/.env` was committed to `origin/main` from the repo's first commit
  until the 2026-08-08 audit removed it from tracking.
- **Untracking a leaked secret does not rotate it.** If a secret was ever pushed to a
  remote, treat it as compromised permanently — `git rm` only stops future commits
  from including it, it does not remove it from history. The Supabase key exposed via
  `deployment/docker/.env` needs to be rotated in the Supabase dashboard independent of
  the git cleanup (Settings → API → regenerate secret key).
- Use `.env.example` as the template for any new environment file — keep it in sync
  with `fastapi_app/config.py`'s `Settings` fields, with placeholder (never real)
  values.
- `deployment/docker/.env` should be treated identically to the root `.env` going
  forward: gitignored, never committed, distributed to collaborators out-of-band.

## Authentication

- JWT (HS256, `python-jose`), issued on `/api/v1/auth/login`, `/register`, or
  `/firebase/exchange`. Validated on every protected route via
  `fastapi_app/security.py`'s `get_current_user`, checking signature, expiry, issuer,
  and audience.
- `JWT_SECRET_KEY` **must** be a strong, non-default value outside of local
  development — `fastapi_app/config.py`'s `validate_secrets` raises on startup if
  `ENVIRONMENT` is `staging`/`production` and the key is unset or still `change-me`.
  Rotate it periodically; rotating it invalidates all outstanding tokens (no refresh-
  token revocation list exists — see Recommendations below).
- Passwords are hashed with `passlib` (`pbkdf2_sha256` primary; `bcrypt` accepted for
  hashes created before that default changed — check `fastapi_app/security.py` if this
  matters for your deployment).
- Firebase sign-in verifies the ID token against Google's public keys
  (`google-auth`) before trusting any claim in it — tokens aren't accepted at face
  value.

## Authorization

- `fastapi_app/security.py` exposes a `require_roles(*roles)` dependency for
  role-gated routes. Roles observed in the schema: `user`, `guardian` (see
  `schemas.py`'s `FirebaseTokenExchangeRequest`).
- Resource ownership is checked explicitly where it matters — e.g.
  `routers/devices.py`'s heartbeat endpoint 404s if the device doesn't belong to the
  requesting user, rather than 403ing after a lookup that would otherwise leak
  existence. Apply the same pattern to any new per-user resource route.

## Evidence at rest

Emergency recordings are the most sensitive data this system holds — audio and
video of an assault in progress — and they are handled on three rules:

- **Sealed before storage.** `EvidenceStore` encrypts with AES-256-GCM before
  any backend receives a byte (`services/evidence_store.py`). The encryption
  deliberately did not move down into the storage layer, so no backend can
  accidentally persist plaintext: it is never given any. A failed
  authentication tag is refused rather than returned, because bytes that may
  have been altered are not evidence of anything.
- **Never reachable by URL alone.** Retrieval goes through
  `GET /api/v1/media/evidence/{id}` — authenticated, ownership-checked and
  streamed. No public bucket, no CDN path, no signed URL is ever issued, so a
  leaked link is not enough to view a recording.
- **Stored somewhere durable.** Set `SUPABASE_URL` and `SUPABASE_SECRET_KEY`
  and evidence goes to a private Supabase Storage bucket. Left unset it falls
  back to `EVIDENCE_STORAGE_DIR` on the application server's own disk —
  correct for a self-hosted deployment with a real volume, and **silently
  destructive on any host with an ephemeral filesystem**, where every deploy
  and restart deletes it. Uploads still return 201 and the database row still
  persists, so nothing looks wrong until the recording is asked for.

The bucket must be private, and `deployment/sql/supabase_setup.sql` creates it
that way with a service-role-only policy rather than leaving it to a dashboard
click. Use the secret (service_role) key, never the publishable one — the
publishable key is designed to be distributed to clients.

## Android permissions and the foreground service

A paired glove keeps detecting while the phone is pocketed, which requires a
foreground service — `FOREGROUND_SERVICE_CONNECTED_DEVICE` plus a `<service>`
declared `connectedDevice|location`. Three properties are deliberate:

- **It runs only while a glove is connected**, not for the app's lifetime. There
  is nothing to keep alive otherwise, and a persistent notification over no
  device would claim a protection that is not running.
- **The persistent notification is not a cost to minimise.** It is the user's
  only way to see that background detection is still alive, and Android's way of
  disclosing that an app is doing work she cannot see.
- **Starting it can fail**, and the UI says so. Notification permission can be
  denied and OEMs kill background work; the app reports the platform's answer
  rather than assuming its request succeeded. A safety control that claims to be
  running when it is not is worse than one that is plainly off.

The service holds no data. Classifications arrive over BLE, feed the vote, and
are discarded; only a resulting incident is ever persisted.

## Known limitations / recommendations

Carried forward from the archived project reports and reconfirmed in the 2026-08-08
audit — none of these are fixed as part of this audit, they're flagged for follow-up:

- **Rate limiting is in place but is per-process, not distributed.**
  `fastapi_app/rate_limit.py` applies a sliding window keyed by client address,
  wired as middleware in `main.py` and disabled in development. It is orthogonal
  to the per-account lockout: the lockout stops someone guessing one password,
  this raises the cost of spraying one password across many accounts, farming
  sign-ups, or hammering the OTP and reset routes, each of which sends real email
  and costs real money. Two limits it does not exceed: the window lives in
  process memory, so behind N workers the effective quota is N times the setting;
  and the client is identified by `X-Forwarded-For` where present, which is only
  trustworthy behind a proxy that overwrites it. Render does; a direct-to-app
  deployment would let an attacker rotate the header. A shared Redis counter is
  the upgrade, and Redis is already in the stack.
- **No refresh-token revocation** — a leaked refresh token remains valid until it
  naturally expires (`REFRESH_TOKEN_EXPIRE_DAYS`, default 7). Consider a token
  denylist (Redis is already in the stack) if this matters for your threat model.
- **Supabase RLS**: the archived `docs/archive/TECHNICAL_INVENTORY.md` flagged that
  Supabase row-level security was configured to allow all operations at the time it
  was written — verify current RLS policy on the `events` table
  (`deployment/sql/supabase_setup.sql`) before relying on Supabase-side access control.
- **The legacy Flask gateway was deleted on 2026-08-15.** If you restore it from git
  history, treat it as unmaintained and do not run it in any environment that
  handles real user data; it predates the current security review and is kept for
  reference only.
- **CORS**: `ALLOW_ORIGINS` defaults to localhost origins; `ALLOW_ORIGIN_REGEX`
  auto-relaxes to localhost-only in development. Double-check both are tightened for
  any non-local deployment.
- **`/api/v1/media/sign-upload`** validates `resource_type` against an allowlist and
  rejects `..` in the folder name — reasonable, but Cloudinary credentials
  (`CLOUDINARY_API_SECRET`) are held server-side and used to sign; keep them out of
  any client-exposed config.
- **MQTT**: `MQTT_TLS_ENABLED` exists as a setting but defaults to `False` — confirm
  it's `True` for any deployment where device telemetry traverses an untrusted
  network, matching the glove firmware's own TLS (port 8883) expectation.
