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

## Known limitations / recommendations

Carried forward from the archived project reports and reconfirmed in the 2026-08-08
audit — none of these are fixed as part of this audit, they're flagged for follow-up:

- **No rate limiting** on any endpoint, including `/auth/login` and
  `/auth/register` — brute-force and credential-stuffing risk. Add a rate limiter
  (e.g. `slowapi`) before any public deployment.
- **No refresh-token revocation** — a leaked refresh token remains valid until it
  naturally expires (`REFRESH_TOKEN_EXPIRE_DAYS`, default 7). Consider a token
  denylist (Redis is already in the stack) if this matters for your threat model.
- **Supabase RLS**: the archived `docs/archive/TECHNICAL_INVENTORY.md` flagged that
  Supabase row-level security was configured to allow all operations at the time it
  was written — verify current RLS policy on the `events` table
  (`supabase_setup.sql`) before relying on Supabase-side access control.
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
