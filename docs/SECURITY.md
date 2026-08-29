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

## Outbound email is an abuse surface, not just a feature

`POST /users/me/emergency-contacts/{id}/verify/send` is the only
authenticated route that sends mail to an address the *caller* chose. Until
2026-08-30 it had no rate limit, while every other mail-sending route did --
the action sits past a path parameter and no prefix rule reached it.

Unlimited, an account could add any address as a "contact" and loop the
endpoint to bomb that inbox from SafeHer's verified sender. The expensive
part is not the victim's mailbox or the delivery credits: it is the sending
domain's reputation. A domain marked as a spam source stops delivering the
emergency alerts this system exists to send, which turns an abuse problem
into a safety one.

It is now capped at 12 per hour per client, and
`tests/test_outbound_email_abuse.py` pins both the limit and its blast
radius -- reading or editing the contact list stays unthrottled, because
rate-limiting someone's access to her own contacts during an emergency
would be a worse bug than the one being fixed.

**When adding a route that sends anything to a third party, add a rule for
it in the same commit.**

## Authorization is enforced per route, and now proven per route

Every route that accepts an id re-derives ownership from the token; a
client-supplied id is an assertion, never a permission. Missing and
not-yours return the same 404, so the API does not confirm that an object
exists to someone not entitled to it.

The gap was never the checks, it was the proof. A 2026-08-30 sweep of all
22 id-bearing routes found every one correctly guarded but two with no test
at all: the live alert WebSocket and the device heartbeat. Both now have
cross-account tests, and `TestRouteRegistry` in
`tests/test_realtime_and_device_isolation.py` fails the suite if a new
id-bearing route appears without being classified -- so the next one cannot
go untested the way these did.

Two routes are deliberately unauthenticated: `GET /share/{token}` and
`GET /share/{token}/evidence/{media_id}`. There the token *is* the
credential -- 256 bits of `secrets`, stored only as a SHA-256 hash,
expiring, revocable, and scoped so a valid token cannot reach a different
incident's evidence. That exemption is asserted in the registry so it
cannot quietly spread to a third route.

## The WebSocket credential is a ticket, not the access token

A WebSocket handshake opened from a browser carries no `Authorization`
header -- the JavaScript API has nowhere to put one -- so whatever
authenticates it must travel in the URL. Query strings are written into
proxy and access logs, kept in history, and forwarded in referrers, which
makes a URL the worst place for a credential.

The fix is not to move the access token but to send something else.
`POST /api/v1/ws/ticket` is authenticated normally, so the access token
stays in a header, and returns a ticket that lives ~30 seconds and opens
nothing but the alert feed -- `decode_token` refuses it wherever an access
token is expected, which is asserted by a test. A ticket recovered from a
log has been useless for a long while by the time anyone reads it.

It is a signed JWT rather than a random string in a table, deliberately. A
stored ticket would be single-use, which is stricter, but it would live in
one worker's memory: minted on one process and redeemed on another it would
simply fail, and the reconnect loop would look like a flaky network to the
one person who needs the live feed.

`WS_ALLOW_LEGACY_TOKEN_QUERY` re-enables the old `?token=` handshake and
**defaults to false**. It exists so an already-installed build does not lose
its live feed the moment the backend updates; turn it off once those builds
are gone. The compatibility path still enforces ownership -- an escape hatch
that skipped that would be far worse than the logging problem it postpones.

## Roles are assigned by the server

`POST /auth/firebase/exchange` used to accept a `role` in the request body,
allow-listed to `user` or `guardian` and applied when the account was
provisioned. It granted nothing, because `require_roles` in
`fastapi_app/security.py` is used by no route -- and that was exactly the
danger. The first route gated on `guardian` would have turned a field the
caller chose at sign-up into privilege escalation, and whoever wrote that
route would have had no reason to suspect it.

The field is gone from the schema and accounts provision as `user`. Pydantic
ignores unknown fields, so a client still sending one is simply not listened
to. **Elevating an account is an operator action.** If `require_roles` is
ever wired to a route, check first that nothing else lets a caller choose
its own role.

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
