# SafeHer Mobile Architecture

## High-Level Modules

- `lib/app/core`
  - Environment config
  - API client and error handling
  - Realtime gateways (WebSocket, MQTT)
  - Device connectivity, secure storage, encryption, offline database
- `lib/app/features`
  - Feature-first modules for auth, dashboard, incidents, contacts, SOS, settings, and more
  - Data-layer repositories for auth and safety flows
- `lib/app/shared`
  - Domain models
  - Global app controllers and providers
  - Shared widgets and design primitives

## State Management

- Riverpod powers app-wide state.
- `SessionController` handles onboarding/auth/session preferences.
- `SafetyController` manages threat state, SOS flow, contact/incident updates, and background heartbeat sync.

## Data Flow

1. UI triggers controller actions.
2. Controllers delegate persistence/network work to repositories.
3. Repositories coordinate local cache and backend APIs.
4. Realtime channels feed events into safety timeline state.

## Security

- JWT and sensitive keys are stored via secure storage.
- Evidence payloads are encrypted before disk write.
- Biometric gate can re-authenticate session access.

## Offline Strategy

- Safety-critical records (incidents/contacts/notifications) are cached locally.
- Heartbeat and emergency API failures trigger offline mode fallback.
- Cached data remains accessible while disconnected.
