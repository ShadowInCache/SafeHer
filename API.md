# API Reference

Base URL: `http://<host>:<port>` (default `API_PORT=5000`, see `fastapi_app/config.py`;
`deployment/docker/docker-compose.yml` may expose a different port — check `.env`).
All resource routes are mounted under `/api/v1`. Interactive docs are served at
`/api/v1/docs` while the app is running.

This documents `fastapi_app/`, the current backend. It does **not** document
`legacy_flask_gateway/`, which is unused — see `docs/archive/BACKEND_INTEGRATION.md`
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
| POST | `/emergency` | Bearer | `{incident_id?, auto?, severity, summary, location, contacts?, metadata?}` — user- or system-initiated SOS. Always creates an `Incident` + `Location` row, broadcasts, and pushes. → `IncidentPublic` (201) |
| POST | `/heartbeat` | Bearer | `{timestamp, threat_score, location}` — periodic monitoring ping, updates the live score. → `{status, score, level}` (202) |
| GET | `/live` | Bearer | → `{live_score: {score, level, updated_at}, recent_incidents: [...]}` |

Threat levels are derived from a 0–100 score: `< 35` low, `35–59` medium, `60–79`
high, `≥ 80` critical.

**Known limitation:** `/alerts/live` reads from an in-process `dict`
(`_latest_scores` in `routers/alerts.py`), not the database. It resets on every
backend restart and won't be consistent across multiple backend instances/replicas —
fine for a single dev/staging instance, not safe to scale horizontally as-is.

### WebSocket (`/api/v1/ws`)

| Path | Description |
|---|---|
| `WS /api/v1/ws/alerts/{user_id}` | Live feed of `threat_alert` / `emergency_alert` events for that user, broadcast by `fastapi_app/realtime.py` whenever `/alerts/process-threat` or `/alerts/emergency` create an incident. |

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
