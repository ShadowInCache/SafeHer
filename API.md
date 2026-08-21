# API Reference

Base URL: `http://<host>:<port>` (default `API_PORT=5000`, see `fastapi_app/config.py`;
`deployment/docker/docker-compose.yml` may expose a different port — check `.env`).
All resource routes are mounted under `/api/v1`. Interactive docs are served at
`/api/v1/docs` while the app is running.

This documents `fastapi_app/`, the current backend. It does **not** document
the deleted Flask gateway — see `docs/archive/BACKEND_INTEGRATION.md`
if you need the old Flask gateway's shape for historical comparison.

## Authentication

Two ways to obtain a session, both end in the same JWT pair:

**Email + password**
```
POST /api/v1/auth/register
POST /api/v1/auth/login
```

**Firebase**
```
POST /api/v1/auth/firebase/exchange
```
Verifies a Firebase ID token (via `google-auth`), auto-provisions a local user on
first sign-in, and issues the same JWT pair.

Every response is:
```json
{ "access_token": "...", "refresh_token": "...", "token_type": "bearer" }
```

Send it back as `Authorization: Bearer <access_token>` on every subsequent request.
Tokens are HS256-signed (`python-jose`), carry `sub` (email), `role`, `exp`, and
`type` (`access`/`refresh`) claims, and are validated against `JWT_ISSUER` /
`JWT_AUDIENCE`. There are no server-side sessions — `POST /auth/logout` is a no-op
(204) that exists only for client symmetry; tokens remain valid until they expire.

## Endpoints

### Health

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/health`, `/api/v1/health` | none | Liveness check |
| GET | `/status`, `/api/v1/status` | none | Extended status |

### Auth (`/api/v1/auth`)

| Method | Path | Auth | Body → Response |
|---|---|---|---|
| POST | `/register` | none | `{email, password, full_name?, role?}` → `UserPublic` (201) |
| POST | `/login` | none | `{email, password}` → `Token`. 401 on bad credentials, 403 if inactive |
| POST | `/firebase/exchange` | none | `{id_token, role?, full_name?}` → `Token` |
| GET | `/me` | Bearer | → `UserPublic` |
| POST | `/refresh` | none | `{refresh_token}` → new `Token` pair |
| POST | `/logout` | Bearer | 204, client-side token deletion |

### Users (`/api/v1/users`)

| Method | Path | Auth | Body → Response |
|---|---|---|---|
| GET | `/me` | Bearer | → `UserPublic` |
| GET | `/me/emergency-contacts` | Bearer | → `EmergencyContactPublic[]` |
| POST | `/me/emergency-contacts` | Bearer | `{name, phone, email?, relationship?, priority?}` → `EmergencyContactPublic` |
| PUT | `/me/emergency-contacts/{contact_id}` | Bearer | partial update → `EmergencyContactPublic` |
| DELETE | `/me/emergency-contacts/{contact_id}` | Bearer | 204 |
| GET | `/me/export` | Bearer | → one JSON document with the account, emergency contacts, devices, incidents, locations, safe journeys, evidence *references* and notification log. GDPR Art. 15, the counterpart to `DELETE /auth/account`. Carries no password/OTP/PIN hashes or share tokens, and links evidence by id rather than inlining it — an export ends up in a Downloads folder. |

### Media (`/api/v1/media`)

| Method | Path | Auth | Body → Response |
|---|---|---|---|
| POST | `/sign-upload` | Bearer | `{folder?, public_id?, resource_type?}` → Cloudinary signed-upload params (`cloud_name`, `api_key`, `signature`, `timestamp`, `upload_url`, ...). 400 if Cloudinary isn't configured or `resource_type` is invalid. The client uploads directly to Cloudinary with these params — the file itself never passes through this backend. |

### Incidents (`/api/v1/incidents`)

| Method | Path | Auth | Body → Response |
|---|---|---|---|
| POST | `/` | Bearer | `{title, description?, threat_level?, evidence_url?, ...}` → `IncidentPublic` (201) |
| GET | `/` | Bearer | → `IncidentPublic[]` (current user's incidents) |
| GET | `/{incident_id}` | Bearer | → `IncidentPublic` |

### Devices (`/api/v1/devices`)

| Method | Path | Auth | Body → Response |
|---|---|---|---|
| POST | `/register` | Bearer | `{device_name, device_type}` → `DevicePublic` |
| GET | `/me` | Bearer | → `DevicePublic[]` |
| POST | `/{device_id}/heartbeat` | Bearer | `{battery_level?, signal_strength?, firmware_version?}` → 204. 404 if the device isn't owned by the caller |

### Notifications (`/api/v1/notifications`)

| Method | Path | Auth | Body → Response |
|---|---|---|---|
| POST | `/register-token` | Bearer | `{token, device_id?}` → 204. 400 if `token` is empty |
| GET | `/tokens` | Bearer | → `{tokens: [{id, device_id, token, created_at}]}` |

### Alerts (`/api/v1/alerts`) — the core threat pipeline

| Method | Path | Auth | Body → Response |
|---|---|---|---|
| POST | `/process-threat` | Bearer | `{device_id, threat_type, confidence, summary, details?, location?}` — forwards to the external processor (`services/processor_client.py`), creates an `Incident` + WebSocket broadcast + best-effort FCM push if a threat is detected. → `{processor, threat_detected, live_score}` |
| POST | `/emergency` | Bearer | `{incident_id?, auto?, severity, summary, location, contacts?, metadata?}` — user- or system-initiated SOS. Creates an `Incident` + `Location` row, broadcasts, pushes, and **queues** the contact fan-out. Returns as soon as the incident is durable, with `dispatch_status: "in_progress"`. → `IncidentPublic` (201) |
| GET | `/emergency/{incident_id}/dispatch` | Bearer, owner-only | → `{incident_id, status, contacts_total, contacts_notified, contacts_reached[], contacts_failed[], completed_at}` — poll this for the fan-out result. 404 for an incident belonging to anyone else. |
| POST | `/heartbeat` | Bearer | `{timestamp, threat_score, location}` — periodic monitoring ping, updates the live score. → `{status, score, level}` (202) |
| GET | `/live` | Bearer | → `{live_score: {score, level, updated_at}, recent_incidents: [...]}` |

Threat levels are derived from a 0–100 score: `< 35` low, `35–59` medium, `60–79`
high, `≥ 80` critical.

**The SOS does not wait for the fan-out.** Every contact is attempted on up to
three channels with three attempts each, and a channel whose port is blocked
fails by *timing out* rather than refusing — two contacts against a blocked
SMTP port measured around two minutes, while the mobile client gives up at
fifteen seconds. `POST /emergency` therefore commits the incident, schedules
the fan-out as a background task and answers immediately; the outcome is read
from `GET /emergency/{id}/dispatch` or pushed as a `dispatch_complete`
WebSocket event.

**`incident_id` is the idempotency key, and the client should send one.** A
phone that never received a response cannot know whether the request arrived.
Replaying the same id returns the existing incident untouched instead of
filing a second emergency and messaging every contact twice. An id that
belongs to *another* user does not fail the request — a new id is issued and
the SOS proceeds, because no error is worth refusing an emergency over.

`dispatch_status` is `null` on any incident that was never dispatched, which
is deliberately distinct from `"complete"` with zero reached. Likewise
`contacts_notified: null` means "no dispatch attempted", `0` means "attempted
and reached nobody".

**Known limitation:** `/alerts/live` reads from an in-process `dict`
(`_latest_scores` in `routers/alerts.py`), not the database. It resets on every
backend restart and won't be consistent across multiple backend instances/replicas —
fine for a single dev/staging instance, not safe to scale horizontally as-is.

### WebSocket (`/api/v1/ws`)

| Path | Description |
|---|---|
| `WS /api/v1/ws/alerts/{user_id}` | Live feed of `threat_alert` / `emergency_alert` events for that user, broadcast by `fastapi_app/realtime.py` whenever `/alerts/process-threat` or `/alerts/emergency` create an incident. Also carries `dispatch_complete` (`{incident_id, contacts_total, contacts_notified, contacts_reached[], contacts_failed[]}`) when the background fan-out finishes — the push counterpart to polling `GET /alerts/emergency/{id}/dispatch`. |

## Error responses

Standard FastAPI/Pydantic shape:
```json
{ "detail": "human-readable message" }
```
or, for request validation errors (422):
```json
{ "detail": [ { "loc": ["body", "field"], "msg": "...", "type": "..." } ] }
```

Common status codes used across the API: `400` (bad input / precondition, e.g.
duplicate registration), `401` (missing/invalid/expired token), `403` (inactive
user), `404` (resource not found or not owned by caller), `422` (schema validation).

## What the mobile app actually calls today

As of this audit, `mobile/`'s repositories are largely mock-backed
(`AppFlavor.isMock`); the real-API integration layer is an in-progress migration, not
a finished 1:1 wiring of every screen to the endpoints above. Treat this document as
the backend's contract, not a description of the mobile app's current network calls.
