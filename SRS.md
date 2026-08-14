# SAFEHER — CLAUDE CODE MASTER PROMPT
## AI-Powered Wearable Safety Ecosystem
### Software Requirements Specification + Complete Build Guide
#### Version 2.1 | Claude Code Agentic Execution Format

---

> **HOW TO USE THIS FILE**
> Place this file as `CLAUDE.md` in your project root.
> Then run: `claude` in that directory.
> Claude Code will read this file automatically and begin execution.
> Alternatively, run: `claude --print < SAFEHER_CLAUDE_CODE_PROMPT.md`

---

## ═══════════════════════════════════════════════════════════
## MISSION BRIEFING
## ═══════════════════════════════════════════════════════════

You are acting simultaneously as:
- **Principal Software Architect** — system design decisions
- **Flutter Staff Engineer** — mobile implementation
- **Senior Product Designer** — visual identity and UX
- **Motion Designer** — animation system
- **CTO** — end-to-end delivery accountability

You are building **SafeHer** — the world's most capable AI-powered
wearable safety ecosystem for women.

### Your Non-Negotiable Execution Rules

```
RULE 1:  Build → Run → Verify → Test → Fix → Commit → Continue
RULE 2:  Never generate placeholders, TODOs, or fake integrations
RULE 3:  Every file created must be real, runnable, and tested
RULE 4:  Do NOT move to the next task until the current one passes
RULE 5:  All secrets from environment variables — zero hardcoded creds
RULE 6:  All animations must check MediaQuery.disableAnimations first
RULE 7:  All state via Riverpod — never setState()
RULE 8:  All navigation via GoRouter — never Navigator.push()
RULE 9:  Every interactive widget must have Semantics() labels
RULE 10: RepaintBoundary on every independently-animating widget
```

### Blocking Conditions (Stop and Fix Before Continuing)

```bash
# These commands must all pass before moving to any next phase:
flutter analyze                          # must return 0 issues
flutter test --coverage                  # must be > 70% coverage
flutter build apk --release              # must succeed with 0 errors
dart run build_runner build              # must complete with 0 conflicts
```

---

## ═══════════════════════════════════════════════════════════
## PART 1 — SOFTWARE REQUIREMENTS SPECIFICATION (SRS)
## ═══════════════════════════════════════════════════════════

---

## SRS §1 — Executive Overview

### 1.1 Product Vision

SafeHer is an end-to-end AI-powered personal safety ecosystem
designed exclusively for women. It combines:

- **Edge-computing wearables**: Smart Glove (ESP32 + MPU6050) and
  Smart Glasses (ESP32-CAM + microphone)
- **Production-grade mobile app**: Flutter, iOS 14+, Android 10+
- **Cloud AI inference**: Motion, Vision, Audio, and Summarisation models
- **Real-time monitoring dashboard**: React admin panel

The system detects danger proactively, collects forensic evidence,
dispatches emergency responses — all with minimal user interaction.

**Core Principle**: Safety technology must be invisible until needed.

### 1.2 Mission Statement

```
To build a fully working, scalable, reliable, and secure AI-powered
wearable safety ecosystem that proactively protects women by:
  · Detecting danger within 2 seconds
  · Collecting forensic evidence automatically
  · Calculating real-time threat scores (0.0–1.0)
  · Generating emergency alerts within 5 seconds
  · Tracking location with GPS + breadcrumbs
  · Notifying emergency contacts via FCM + SMS + WhatsApp
  · Generating AI incident reports with chain-of-custody
  · Storing encrypted evidence in cloud storage
  · Displaying analytics on admin dashboard
All with minimum user interaction and zero dependency on manual
activation.
```

### 1.3 Measurable Goals

| Goal | Metric | Target |
|------|--------|--------|
| Threat detection speed | Sensor event → AI score | < 2 seconds |
| Alert dispatch speed | Score breach → FCM sent | < 5 seconds |
| True positive rate | AI detection accuracy | > 95% |
| False positive rate | False alerts / total alerts | < 3% |
| Backend uptime | Monthly availability | 99.9% |
| Offline operation | Max duration without connectivity | 72 hours |
| Concurrent users | Scalability target at launch | 1,000,000 |
| Accessibility | WCAG compliance level | 2.1 AA |
| App cold start | Time to interactive on Pixel 6a | < 2 seconds |
| APK size | Release build | < 80 MB |

### 1.4 Scope

| Component | In Scope | Out of Scope |
|-----------|----------|--------------|
| Mobile App | iOS 14+, Android 10+ | Web browser, Windows |
| Smart Glove | ESP32 prototype + firmware | Mass-production PCB |
| Smart Glasses | ESP32-CAM prototype | Optical lenses |
| Backend | REST + WebSocket + MQTT | gRPC, GraphQL |
| AI Models | Motion, Vision, Audio, Summarisation | Custom LLM training |
| Dashboard | React admin analytics | Mobile admin app |
| Cloud | GCP Cloud Run + Firebase | AWS, Azure |
| Auth | Firebase (email, Google, Apple) | Enterprise SSO |

---

## SRS §2 — Stakeholders & User Personas

### 2.1 Primary User — The Protected Woman

```
Age range:    16–50 years
Tech literacy: Low to moderate
Context:      Daily commute, night travel, campus, public transport
Core need:    Absolute confidence help is coming — no fumbling required
Pain points:  Slow manual SOS, dead battery, no witnesses, no evidence
```

### 2.2 Emergency Contact

```
Relationship: Trusted family member or friend
App needed:   No — receives SMS + web link
Needs:        Instant clarity on who, where, what happened
```

### 2.3 Platform Administrator

```
Role:    Manages users, devices, AI models, system health
Access:  React admin dashboard
Actions: User management, OTA campaigns, model deployments, analytics
```

### 2.4 Indirect Stakeholders

| Stakeholder | Interest | Concern |
|-------------|----------|---------|
| Law Enforcement | Forensic evidence access | Chain of custody |
| Healthcare | Trauma response coordination | HIPAA compliance |
| Telecom Providers | SMS gateway reliability | Low-signal delivery |
| Device Manufacturers | Hardware integration spec | OTA update process |
| NGOs / Safety Orgs | Impact analytics | Survivor privacy |

---

## SRS §3 — System Architecture

### 3.1 Architecture Stack

```
Pattern:   Hybrid Event-Driven + Microservices + Clean Architecture + Edge AI
Protocols: MQTT (device→cloud) · WebSocket (realtime UI) · REST (CRUD)
Mobile:    Flutter 3.22+ · Riverpod 2.5+ · GoRouter 13+ · Material 3
Backend:   Python FastAPI (per microservice)
Database:  Cloud Firestore (primary) · Redis (cache + pub/sub queue)
Storage:   Firebase Storage (media evidence)
Auth:      Firebase Authentication
AI:        TFLite Micro (edge) + FastAPI Cloud Run (cloud inference)
Dashboard: React 18 + Recharts + TailwindCSS
Deploy:    Docker → GCP Cloud Run + Firebase Hosting
Monitor:   Sentry (errors) · Grafana + Prometheus (metrics)
```

### 3.2 Monorepo Structure

```
safeher/
├── mobile_app/                    ← Flutter application
│   ├── lib/
│   │   ├── core/
│   │   │   ├── theme/             ← Design system tokens
│   │   │   ├── animations/        ← Animation token system
│   │   │   ├── router/            ← GoRouter configuration
│   │   │   └── di/                ← GetIt + Injectable DI
│   │   ├── shared/
│   │   │   └── components/        ← Reusable component library
│   │   ├── features/
│   │   │   ├── auth/
│   │   │   ├── home/
│   │   │   ├── monitoring/
│   │   │   ├── emergency/
│   │   │   ├── devices/
│   │   │   ├── dashboard/
│   │   │   ├── reports/
│   │   │   ├── search/
│   │   │   └── profile/
│   │   └── main.dart
│   └── test/
├── backend/
│   └── services/
│       ├── auth_service/
│       ├── user_service/
│       ├── device_service/
│       ├── alert_service/
│       ├── media_service/
│       ├── report_service/
│       ├── analytics_service/
│       ├── notification_service/
│       └── admin_service/
├── ai_services/
│   ├── motion_model/
│   ├── weapon_detection/
│   ├── voice_analysis/
│   ├── incident_summarizer/
│   └── fusion_engine/
├── firmware/
│   ├── smart_glove/
│   └── smart_glasses/
├── dashboard/                     ← React admin panel
├── cloud/
│   ├── firestore/                 ← Rules + indexes
│   ├── functions/                 ← Cloud Functions
│   └── terraform/                 ← IaC
├── deployment/
│   └── docker/
├── docs/
├── tests/
│   ├── unit/
│   ├── integration/
│   ├── e2e/
│   └── load/
└── scripts/
```

### 3.3 Five-Layer Data Flow

```
LAYER 1 — EDGE (Firmware)
  Smart Glove:   MPU6050 + flex sensors → ESP32 → TFLite Micro
                 → classify gesture → MQTT publish (QoS 1)
  Smart Glasses: OV2640 camera → JPEG buffer → HTTPS chunked upload
                 INMP441 mic → PCM audio → MQTT publish (QoS 1)

LAYER 2 — MOBILE (Flutter)
  MQTT subscriber → sensor event queue → Riverpod StreamProvider
  GPS: every 3s in alert mode; every 30s in idle mode
  Hive offline queue: stores events when network unavailable
  Evidence recorder: Camera + Audio API → encrypted local storage

LAYER 3 — BACKEND (FastAPI Microservices)
  API Gateway → JWT RS256 validation → rate limiting → routing
  Redis Pub/Sub → async inter-service communication
  WebSocket server → push real-time state to mobile + dashboard
  EMQX MQTT broker → device command/control channel

LAYER 4 — AI PLATFORM
  Motion Model:  Sensor window → BiLSTM → 5-class classification
  Weapon Model:  JPEG frame → YOLOv8-nano → detection + confidence
  Voice Model:   PCM audio → mel-spectrogram → EfficientNet-B0
  Fusion Engine: Weighted score + EMA smoothing + context boosters
  Summariser:    GPT-4o multimodal → forensic incident narrative

LAYER 5 — RESPONSE
  Threshold breach (score ≥ 0.75) → Emergency Protocol
  Parallel dispatch: FCM push + SMS + WhatsApp + email
  Evidence package signed URL generated
  Incident report auto-generated
  Dashboard WebSocket broadcast
```

---

## SRS §4 — Functional Requirements

### 4.1 Authentication

| ID | Requirement | Priority | Acceptance Criterion |
|----|-------------|----------|---------------------|
| FR-AUTH-01 | Email + password with OTP email verification | MUST | OTP within 30s; account inactive until verified |
| FR-AUTH-02 | Google Sign-In via Firebase Auth | MUST | One-tap login in < 2s |
| FR-AUTH-03 | Apple Sign-In (iOS) | MUST | Required for App Store |
| FR-AUTH-04 | JWT access token (15 min) + refresh (30 days) | MUST | Silent refresh without UX disruption |
| FR-AUTH-05 | Biometric unlock (Face ID / Fingerprint) | SHOULD | Prompt within 500ms of foreground |
| FR-AUTH-06 | Session invalidation on password change | MUST | All tokens revoked across all devices |
| FR-AUTH-07 | Rate limit: 5 failed logins → 15-min lockout | MUST | Countdown shown in UI; lockout email sent |
| FR-AUTH-08 | Account deletion with 30-day grace period | MUST | GDPR Article 17 compliant |

### 4.2 Device Management

| ID | Requirement | Priority | Acceptance Criterion |
|----|-------------|----------|---------------------|
| FR-DEV-01 | Pair Smart Glove via BLE scan + 6-digit PIN | MUST | Pairing in < 10s; shown in device list |
| FR-DEV-02 | Pair Smart Glasses via BLE scan + 6-digit PIN | MUST | Pairing in < 10s |
| FR-DEV-03 | Real-time battery level for each device | MUST | Updates every 60s; low-battery at 20% |
| FR-DEV-04 | Firmware OTA update from admin dashboard | MUST | SHA-256 verified before flash |
| FR-DEV-05 | Device disconnection alert within 5 seconds | MUST | Push notification + in-app banner |
| FR-DEV-06 | Up to 3 device sets per account | SHOULD | Named sets; switchable |
| FR-DEV-07 | Device health diagnostics | SHOULD | Signal, error rate, uptime visible |

### 4.3 Emergency System

| ID | Requirement | Priority | Acceptance Criterion |
|----|-------------|----------|---------------------|
| FR-EMG-01 | Manual SOS — single tap activates emergency | MUST | Alert dispatched within 3s |
| FR-EMG-02 | Auto-SOS when AI threat score ≥ 0.75 | MUST | Zero user interaction required |
| FR-EMG-03 | 10-second countdown with cancel option | MUST | Haptic + visual + audio; cancellable |
| FR-EMG-04 | Alert all contacts via FCM + SMS simultaneously | MUST | All notified within 5s; 3-retry on fail |
| FR-EMG-05 | Alert contains: name, GPS link, time, evidence URL | MUST | SMS < 160 chars with link; full via URL |
| FR-EMG-06 | Auto-start video + audio evidence recording | MUST | Recording begins within 1s of trigger |
| FR-EMG-07 | Evidence encrypted AES-256 at rest + TLS 1.3 in transit | MUST | Verified by automated test suite |
| FR-EMG-08 | False-alarm cancellation within 10s countdown | MUST | Logged but not transmitted; audit trail |
| FR-EMG-09 | Offline emergency: store + transmit on reconnect | MUST | Sent within 30s of connectivity restore |
| FR-EMG-10 | Emergency contacts: up to 10; drag priority order | MUST | OTP confirmation for each added contact |

### 4.4 Live Monitoring

| ID | Requirement | Priority | Acceptance Criterion |
|----|-------------|----------|---------------------|
| FR-MON-01 | Real-time sensor feed from glove displayed in app | MUST | < 500ms latency sensor to UI |
| FR-MON-02 | Live video preview from glasses | SHOULD | MJPEG at ≥ 10 FPS |
| FR-MON-03 | Real-time audio waveform visualisation | SHOULD | 30 FPS waveform update |
| FR-MON-04 | Threat Score gauge updating in real-time | MUST | Colour-coded; smooth spring animation |
| FR-MON-05 | GPS location on map with 5m accuracy | MUST | Renders offline via cached tiles |
| FR-MON-06 | Motion pattern timeline — last 60 seconds | SHOULD | Scrollable; AI classification event pins |

### 4.5 Reports & Analytics

| ID | Requirement | Priority | Acceptance Criterion |
|----|-------------|----------|---------------------|
| FR-RPT-01 | AI-generated incident summary after each alert | MUST | Generated within 30s of incident close |
| FR-RPT-02 | Incident timeline with ±100ms accuracy | MUST | All events chronologically stitched |
| FR-RPT-03 | PDF export of incident report | MUST | Forensic-grade; chain-of-custody hash |
| FR-RPT-04 | Personal safety analytics heatmap | SHOULD | In-app heatmap of safe/unsafe zones |
| FR-RPT-05 | Threat score history chart (30/90/365 days) | SHOULD | Interactive; tap to see event detail |
| FR-RPT-06 | Share incident report via secure link | SHOULD | Expiring URL (7 days); read-only view |

---

## SRS §5 — Non-Functional Requirements

### 5.1 Performance Targets

| Metric | Target | Measurement |
|--------|--------|-------------|
| Threat detection latency (sensor → score) | < 2 seconds E2E | Integration test with timestamp logging |
| Alert dispatch latency (breach → FCM sent) | < 5 seconds | Sentry performance tracing |
| App cold start (Pixel 6a class device) | < 2 seconds | Flutter DevTools Timeline |
| API response time P95 | < 300ms | Grafana / k6 load test |
| API response time P99 | < 500ms | Grafana / k6 load test |
| Concurrent WebSocket connections | 10,000 per instance | Locust stress test |
| Video evidence upload throughput | > 5 Mbps on LTE | Network profiler |
| Dashboard initial paint | < 1.5 seconds | Lighthouse score > 90 |
| Offline queue drain on reconnect | < 30 seconds for 72h backlog | Integration test |
| Animation frame rate | 60fps minimum; 120fps on ProMotion | Flutter DevTools Profile |

### 5.2 Security Requirements

| Domain | Requirement |
|--------|-------------|
| Transport | TLS 1.3 minimum; MQTT over TLS; certificate pinning in mobile app |
| Authentication | Firebase Auth RS256 JWT; PKCE for OAuth flows |
| Authorisation | RBAC: roles user/admin/support; Firestore Security Rules row-level |
| Encryption at Rest | AES-256-GCM for evidence; Firestore Google-managed encryption |
| API Security | Rate limiting per user + IP; OWASP Top-10 mitigations; Pydantic validation |
| Firmware | Signed binaries; reject unsigned OTA; secure boot on ESP32 |
| Secrets | Google Secret Manager only; zero hardcoded credentials; .env never committed |
| Audit | All admin actions → append-only Firestore subcollection with tamper detection |
| Penetration Testing | OWASP ZAP scan every release; annual third-party pentest |
| GDPR / Privacy | Data minimisation; right to erasure API; DPA for all sub-processors |

### 5.3 Reliability & Availability

```
Backend SLA:            99.9% monthly uptime (< 44 min downtime/month)
Firebase dependencies:  Rely on Google SLA (99.95%); fallback for Auth outages
MQTT broker:            Clustered EMQX 3-node quorum; automatic leader election
AI inference:           Cloud primary + TFLite edge fallback on firmware
Database:               Firestore multi-region (us-central1 + eu-west1)
Evidence storage:       Firebase Storage cross-region; 99.999999999% durability
```

### 5.4 Usability & Accessibility

```
Standard:       WCAG 2.1 Level AA
Touch targets:  Minimum 48×48dp on all interactive elements
SOS reach:      Emergency button reachable from any screen within 1 tap
Screen reader:  Full TalkBack (Android) + VoiceOver (iOS) support
Font scaling:   Supports system font scale up to 200%
Contrast ratio: ≥ 4.5:1 for all text; ≥ 3:1 for UI components
RTL support:    Layout ready for future RTL localisation
Reduced motion: All animations respect MediaQuery.disableAnimations
```

---

## SRS §6 — AI Platform Specification

### 6.1 Model Architecture

| Model | Input | Architecture | Output | Target |
|-------|-------|-------------|--------|--------|
| Motion Classifier | 5s window: accel (3-axis) + gyro (3-axis) + flex (5-ch) @ 50Hz → 250×11 tensor | BiLSTM (128 units) + Attention + Dense. TFLite for edge; full model on Cloud Run | `[normal, struggling, falling, running, distress_gesture]` + confidence | > 95% accuracy |
| Weapon Detector | JPEG 640×640 | YOLOv8-nano fine-tuned. INT8 quantised for edge | BBox + class + confidence per detection | mAP@0.5 > 0.88 |
| Voice Analyser | 3s PCM @ 16kHz → mel-spectrogram 128×128 | EfficientNet-B0 CNN. TFLite for edge | `[calm, elevated, aggressive, screaming, crying]` + confidence | > 90% F1 |
| Incident Summariser | Structured incident JSON + optional image frame | GPT-4o via API; fallback Llama-3.1-8B via Ollama | Prose narrative (200–500 words) + key event bullets | Human eval > 4.0/5.0 |

### 6.2 Fusion Engine Algorithm

```python
# Threat Score Computation
threat_score = (0.40 * motion_score) + (0.35 * audio_score) + (0.25 * vision_score)

# Exponential Moving Average smoothing
smoothed(t) = 0.30 * raw(t) + 0.70 * smoothed(t-1)

# Context boosters (additive)
if hour in range(22, 6):              score += 0.10  # night hours
if location in high_risk_zones:       score += 0.05  # area risk
if weapon_confidence > 0.70:          score += 0.15  # weapon detected

# Alert threshold
if smoothed_score >= user.threat_threshold:  # default 0.75
    trigger_emergency_protocol()

# Deduplication window
# Suppress re-trigger for 120 seconds after alert fires
```

### 6.3 AI Serving Infrastructure

```
Serving:        FastAPI services on Cloud Run (GPU-enabled for YOLOv8)
Versioning:     Semantic versioning in Firestore; A/B test by user cohort
Rollback:       Instant traffic split; old version warm for 24h post-deploy
Edge models:    TFLite bundled in firmware; OTA same channel as firmware
Model registry: All versions in Cloud Storage with SHA-256 manifest
Monitoring:     Latency + confidence distribution in Grafana; drift alerts
```

---

## SRS §7 — Backend Microservices

### 7.1 Service Inventory

| Service | Port | Responsibility | Key Endpoints |
|---------|------|----------------|---------------|
| API Gateway | 8000 | JWT validation, rate limiting, routing | /health, /metrics |
| Auth Service | 8001 | Token issuance, refresh, revocation | POST /auth/register, /login, /refresh |
| User Service | 8002 | Profile, contacts, preferences | GET/PUT /users/me, /users/contacts |
| Device Service | 8003 | Pairing, status, OTA management | POST /devices/pair, GET /devices |
| Alert Service | 8004 | Alert creation, deduplication | POST /alerts, GET /alerts/:id |
| Media Service | 8005 | Evidence upload, transcoding, signing | POST /media/upload, GET /media/:id/url |
| Report Service | 8006 | Report generation, PDF export | POST /reports/generate, GET /reports/:id |
| Analytics Service | 8007 | Aggregations, heatmaps, trends | GET /analytics/summary, /heatmap |
| Notification Service | 8008 | FCM, SMS, WhatsApp, email | POST /notifications/send (internal) |
| Admin Service | 8009 | User mgmt, system config, model deploy | GET /admin/users, POST /admin/models |

### 7.2 Core API Schemas

```json
// POST /alerts — Emergency Alert Creation
Request: {
  "trigger_type": "MANUAL | AI_AUTO | GESTURE",
  "threat_score": 0.89,
  "location": { "lat": 17.3850, "lng": 78.4867, "accuracy_m": 5 },
  "device_id": "dev_glove_xyz",
  "evidence_session_id": "sess_abc"
}
Response 201: {
  "alert_id": "alert_789xyz",
  "status": "DISPATCHED",
  "contacts_notified": 3,
  "evidence_upload_url": "https://storage.googleapis.com/...",
  "report_draft_id": "rpt_draft_001"
}

// POST /ai/analyze — Multi-modal Threat Analysis
Request: {
  "session_id": "sess_abc",
  "modalities": ["motion", "audio", "vision"],
  "sensor_window": { "timestamps": [...], "accel_xyz": [...] },
  "audio_chunk_id": "audio_007",
  "image_frame_ids": ["frame_100", "frame_101"]
}
Response 200: {
  "threat_score": 0.87,
  "component_scores": { "motion": 0.92, "audio": 0.81, "vision": 0.88 },
  "detections": {
    "motion": { "class": "struggling", "confidence": 0.92 },
    "audio": { "class": "distress_scream", "confidence": 0.81 },
    "vision": { "class": "weapon_knife", "confidence": 0.88 }
  },
  "recommend_alert": true,
  "analysis_latency_ms": 847
}
```

### 7.3 WebSocket Event Catalogue

| Event | Direction | Payload |
|-------|-----------|---------|
| `threat_score_update` | Server → Client | `{ score, components, timestamp }` |
| `device_status` | Server → Client | `{ device_id, battery_pct, connected, rssi }` |
| `alert_dispatched` | Server → Client | `{ alert_id, contacts_notified, evidence_session }` |
| `location_update` | Server → Client | `{ lat, lng, accuracy_m, timestamp }` |
| `evidence_progress` | Server → Client | `{ session_id, bytes_uploaded, bytes_total, pct }` |
| `sensor_stream` | Client → Server | `{ accel, gyro, flex, timestamp }` (10Hz) |
| `heartbeat` | Both ↔ Both | `{ ts }` (every 30s) |

---

## SRS §8 — Database Schema (Firestore)

### 8.1 users/{userId}

```typescript
{
  id: string,                    // Firebase UID
  email: string,
  phone: string,                 // E.164 format
  first_name: string,
  last_name: string,
  avatar_url?: string,
  created_at: Timestamp,
  updated_at: Timestamp,
  role: "user" | "admin" | "support",
  is_verified: boolean,
  is_active: boolean,
  preferences: {
    threat_threshold: number,    // default 0.75; range 0.50–0.95
    countdown_seconds: number,   // default 10; options 5/10/15
    auto_record: boolean,        // default true
    dark_mode: boolean,
    language: string,            // BCP-47 e.g. "en-IN"
    notifications: {
      push: boolean,
      sms: boolean,
      email: boolean
    }
  },
  stats: {
    total_incidents: number,
    false_alarms: number,
    total_safe_hours: number
  }
}

// Subcollection: users/{userId}/emergency_contacts/{contactId}
{
  name: string,
  phone: string,
  email?: string,
  relationship: string,
  priority: number,             // 1 = highest
  is_confirmed: boolean,        // confirmed via OTP
  notify_via: ("push"|"sms"|"whatsapp"|"email")[],
  added_at: Timestamp
}
```

### 8.2 alerts/{alertId}

```typescript
{
  id: string,
  user_id: string,
  trigger_type: "MANUAL" | "AI_AUTO" | "GESTURE" | "TEST",
  status: "ACTIVE" | "RESOLVED" | "CANCELLED" | "FALSE_ALARM",
  threat_score: number,
  component_scores: { motion: number, audio: number, vision: number },
  location: { lat: number, lng: number, accuracy_m: number, address?: string },
  triggered_at: Timestamp,
  resolved_at?: Timestamp,
  cancelled_at?: Timestamp,
  contacts_notified: number,
  evidence_session_id: string,
  report_id?: string,
  dedup_hash: string            // prevents duplicates within 60s
}
```

### 8.3 incidents/{incidentId}

```typescript
{
  id: string,
  alert_id: string,
  user_id: string,
  ai_summary: string,           // GPT-4o generated prose narrative
  timeline: Array<{
    ts: Timestamp,
    type: string,
    description: string,
    confidence?: number,
    source_device?: string
  }>,
  evidence_refs: Array<{
    type: "video" | "audio" | "photo",
    storage_path: string,
    sha256_hash: string,
    size_bytes: number,
    duration_s?: number
  }>,
  gps_breadcrumbs: Array<{
    lat: number, lng: number, ts: Timestamp, accuracy_m: number
  }>,
  pdf_url?: string,
  chain_of_custody_hash: string, // SHA-256 of full incident JSON
  created_at: Timestamp
}
```

### 8.4 Firestore Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    match /users/{userId} {
      allow read: if isOwner(userId) || isAdmin();
      allow write: if isOwner(userId)
        && !request.resource.data.diff(resource.data)
          .affectedKeys().hasAny(['role', 'is_active']);
    }

    match /users/{userId}/emergency_contacts/{contactId} {
      allow read, write: if isOwner(userId);
    }

    match /alerts/{alertId} {
      allow read: if isOwner(resource.data.user_id);
      allow write: if isServiceAccount();
    }

    match /incidents/{incidentId} {
      allow read: if isOwner(resource.data.user_id);
      allow write: if isServiceAccount();
    }

    match /devices/{deviceId} {
      allow read: if isOwner(resource.data.owner_uid) || isAdmin();
      allow write: if isServiceAccount();
    }

    function isOwner(uid) {
      return request.auth != null && request.auth.uid == uid;
    }
    function isAdmin() {
      return request.auth.token.role == 'admin';
    }
    function isServiceAccount() {
      return request.auth.token.service_account == true;
    }
  }
}
```

### 8.5 Required Composite Indexes

| Collection | Fields | Query Pattern |
|------------|--------|---------------|
| alerts | user_id ASC + triggered_at DESC | User alert history |
| alerts | user_id ASC + status ASC + triggered_at DESC | Active alerts per user |
| incidents | user_id ASC + created_at DESC | User incident list |
| devices | owner_uid ASC + type ASC | User devices by type |
| analytics | user_id ASC + date ASC + event_type ASC | Time-series analytics |

---

## SRS §9 — Firmware Specification

### 9.1 Smart Glove — Hardware BOM

| Component | Specification | Purpose |
|-----------|--------------|---------|
| MCU | ESP32-WROOM-32E (240MHz dual-core, 520KB SRAM) | Compute + WiFi + BLE |
| IMU | MPU6050 (3-axis accel ±16g, gyro ±2000°/s, I²C 400kHz) | Motion detection |
| Flex Sensors | 5× 4.5" resistive (Spectra Symbol) | Finger gesture recognition |
| ADC | ADS1115 (16-bit, 4-channel, I²C) | High-res flex readings |
| Battery | LiPo 1000mAh 3.7V with TP4056 charge controller | ~8h runtime |
| Haptic | ERM vibration motor 3V | Haptic feedback on alert |
| Audio alert | Passive buzzer 5V + NPN transistor | Audio warning |
| LED | NeoPixel WS2812B ×3 | Status indication |

### 9.2 Smart Glove — FreeRTOS Task Architecture

```c
// Core 0 — Protocol Tasks
wifi_manager_task()    // WiFi connect + exponential backoff reconnect
mqtt_client_task()     // EMQX QoS 1 publish; offline queue in NVS flash
ble_server_task()      // GATT server for phone pairing + config
ota_manager_task()     // Check manifest; download; SHA-256 verify; flash

// Core 1 — Sensing Tasks
imu_reader_task()      // MPU6050 @ 50Hz via DMA; ring buffer
flex_reader_task()     // ADS1115 @ 25Hz; 5-channel; ring buffer
ml_inference_task()    // TFLite Micro; classify every 100ms
event_dispatcher_task()// Publish sensor_event to MQTT; deduplication
alert_controller_task()// Activate buzzer/vibration/LED on alert commands

// NVS (Non-Volatile Storage)
// wifi_ssid, wifi_password (encrypted)
// mqtt_uri, device_token
// offline_queue (circular buffer, max 1000 events)
// firmware_version, device_id
```

### 9.3 MQTT Topics

| Topic | Direction | Payload | QoS |
|-------|-----------|---------|-----|
| `safeher/glove/{id}/sensors` | Device → Cloud | `{ ts, ax, ay, az, gx, gy, gz, f0-f4 }` | 1 |
| `safeher/glove/{id}/events` | Device → Cloud | `{ ts, event_type, confidence, battery_pct }` | 1 |
| `safeher/glove/{id}/status` | Device → Cloud | `{ battery_pct, rssi, fw_version, uptime_s }` | 0 |
| `safeher/glove/{id}/cmd` | Cloud → Device | `{ cmd: "alert\|cancel\|ota\|reboot", payload }` | 1 |
| `safeher/glove/{id}/ota` | Cloud → Device | `{ version, url, sha256, size_bytes }` | 1 |

### 9.4 Smart Glasses — Hardware BOM

| Component | Specification | Purpose |
|-----------|--------------|---------|
| MCU + Camera | ESP32-CAM (OV2640 2MP, up to 1600×1200) | Compute + video |
| Microphone | INMP441 I²S digital mic | High-quality audio |
| Battery | LiPo 2000mAh USB-C | ~4h recording; ~12h standby |
| Storage | MicroSD up to 128GB via SPI | Local evidence buffer |
| Status LED | RGB LED | Privacy indicator (legally required) |

---

## SRS §10 — Testing Strategy

### 10.1 Test Pyramid

| Layer | Tool | Coverage Target | What It Tests |
|-------|------|----------------|---------------|
| Unit — Flutter | flutter_test | > 70% line coverage | Dart functions, providers, models |
| Unit — Backend | pytest | > 80% line coverage | Service logic, validation, utilities |
| Unit — AI Models | pytest + TFLite | All inference paths | Output shape, confidence bounds |
| Widget — Flutter | flutter_test + golden_toolkit | All screens + states | UI renders; golden regression |
| Integration — API | pytest + httpx | All endpoint contracts | Full request/response cycle |
| Integration — MQTT | custom pytest fixture | All topics | Publish → subscribe round-trip |
| E2E — Mobile | Patrol (Flutter) | Critical user journeys | Register → pair → alert → verify |
| Load — Backend | k6 | 10k concurrent users | P95 < 300ms; no 5xx under load |
| Security | OWASP ZAP + bandit | All API routes | OWASP Top-10; Python security lint |

### 10.2 Emergency Flow Test Cases

| Test ID | Scenario | Expected Result | Pass Criterion |
|---------|----------|-----------------|----------------|
| TC-EMG-01 | AI threat score ≥ 0.75 while active | Countdown → auto-alert after 10s | Alert dispatched within 13s |
| TC-EMG-02 | User cancels within 10s countdown | Alert cancelled; no contacts notified | FCM NOT sent; logged only |
| TC-EMG-03 | Alert triggered; WiFi drops | Queue in Hive; dispatch on reconnect | Sent within 30s of reconnect |
| TC-EMG-04 | Emergency contact has invalid FCM token | FCM fails; SMS fallback used | SMS received within 10s |
| TC-EMG-05 | Duplicate alert within 60s | Second alert deduplicated | Only 1 alert_id created |
| TC-EMG-06 | All 10 contacts notified in parallel | All 10 notified | All delivered within 5s P95 |
| TC-EMG-07 | Evidence upload while alert active | Video + audio uploaded with progress | Accessible via signed URL < 60s |
| TC-EMG-08 | Incident report post-alert | AI summary + timeline + evidence | PDF generated; hash matches |

---

## SRS §11 — Deployment Architecture

### 11.1 Infrastructure

| Component | Service | Configuration |
|-----------|---------|---------------|
| API Services | GCP Cloud Run | Min 2, Max 100 instances; CPU always-on; VPC connector |
| MQTT Broker | EMQX on GCE (3-node cluster) | e2-medium ×3; internal LB; TLS termination |
| Cache / Queue | Cloud Memorystore (Redis) | 6GB Standard; HA mode |
| Database | Cloud Firestore | Native mode; multi-region nam5; daily GCS backup |
| Storage | Firebase Storage | Multi-region; uniform access; CMEK encrypted |
| CDN | Firebase Hosting + Cloud CDN | Global CDN for dashboard + Flutter web |
| DNS | Cloud DNS | api / ws / dashboard / mqtt subdomains |
| TLS | Google-managed certs | Auto-renew; minimum TLS 1.3 |
| Monitoring | Cloud Monitoring + Grafana Cloud | 28-day retention; alert rules |
| Secrets | Secret Manager | All credentials; auto-rotation |
| IaC | Terraform | All GCP resources coded; state in GCS |

### 11.2 CI/CD Pipeline (GitHub Actions)

```yaml
# On every PR to main:
1.  lint           → dart analyze; ruff; eslint
2.  unit_test      → pytest (≥80%); flutter test (≥70%)
3.  build          → flutter build apk; docker build all services
4.  integration    → pytest against Firebase emulator
5.  security_scan  → bandit; OWASP ZAP baseline
6.  golden_test    → Flutter golden comparison

# On merge to main:
7.  e2e            → Patrol on Android (Firebase Test Lab)
8.  load_smoke     → k6 smoke (100 VUs, 2 min)
9.  deploy_staging → Cloud Run staging + Firebase staging

# On release tag:
10. deploy_prod    → Blue/green Cloud Run production deploy
11. load_full      → k6 full test (10k VUs, 30 min)
12. notify         → Slack + email release notification
```

---

## ═══════════════════════════════════════════════════════════
## PART 2 — FRONTEND DESIGN & IMPLEMENTATION SPECIFICATION
## ═══════════════════════════════════════════════════════════

---

## FRONTEND §1 — Brand Philosophy

```
EMOTION TARGETS:
  Safe        → Warm violet glows; rounded surfaces; slow breathing animations
  Premium     → Glassmorphism; layered depth; 60–120fps motion; expensive spacing
  Trustworthy → Consistent design language; clear hierarchy; no surprises
  Elegant     → Restrained accent use; generous whitespace; typographic clarity
  Modern      → Adaptive layouts; fluid transitions; reactive micro-interactions
  Human       → Friendly copy; avatar-driven UI; empathetic empty states
  High-tech   → Real-time data viz; animated threat gauge; live waveforms

NEVER:
  × Medical aesthetics (no hospital blue, no pill icons)
  × Military aesthetics (no camo, no tactical green)
  × Cyberpunk aesthetics (no neon-on-black, no glitch effects)
  × Overcrowded layouts (no more than 5 information elements per card)

DESIGN SYNTHESIS:
  Spotify's card depth + Apple's motion hierarchy + Tesla's gauge confidence
  + Linear's data minimalism + a warm, feminine-forward colour palette
  = something original and unmistakably SafeHer
```

---

## FRONTEND §2 — Complete Design System

### 2.1 Colour System

**Primary — Deep Violet Scale:**

```dart
// lib/core/theme/app_colors.dart

static const violet50  = Color(0xFFF5F3FF); // light mode subtle BG
static const violet100 = Color(0xFFEDE9FE); // light mode card BG
static const violet200 = Color(0xFFDDD6FE); // dividers; inactive
static const violet400 = Color(0xFFA78BFA); // secondary interactive
static const violet500 = Color(0xFF8B5CF6); // primary (light mode)
static const violet600 = Color(0xFF7C3AED); // PRIMARY BRAND
static const violet700 = Color(0xFF6D28D9); // pressed/active
static const violet800 = Color(0xFF5B21B6); // dark mode primary
static const violet900 = Color(0xFF4C1D95); // dark mode heading
static const violet950 = Color(0xFF2E1065); // dark mode surface tint
```

**Accent — Soft Coral Scale:**

```dart
static const coral400 = Color(0xFFFF8A80); // SOS glow
static const coral500 = Color(0xFFFF6B6B); // SOS button; critical alerts
static const coral600 = Color(0xFFE53935); // danger confirmed
static const coral700 = Color(0xFFC62828); // pressed danger state
```

**Semantic Colours:**

```dart
static const success500 = Color(0xFF10B981); // SAFE state; success toasts
static const success900 = Color(0xFF064E3B); // dark mode success surface
static const warning500 = Color(0xFFF59E0B); // CAUTION/ELEVATED state
static const warning900 = Color(0xFF78350F); // dark mode warning surface
static const info500    = Color(0xFF3B82F6); // informational; connected
```

**Backgrounds:**

```dart
static const dark900 = Color(0xFF0A0A0F); // near-black violet-tinted
static const dark800 = Color(0xFF12121A); // primary surface
static const dark700 = Color(0xFF1C1C28); // elevated (cards)
static const dark600 = Color(0xFF252535); // highest elevation (modals)
static const light50  = Color(0xFFF9FAFB); // light page background
static const light100 = Color(0xFFF3F4F6); // light card surface
```

**Threat State System:**

```dart
// Threat score → visual state mapping
class ThreatColors {
  static Color fill(double score) {
    if (score <= 0.40) return AppColors.success500;  // SAFE
    if (score <= 0.60) return AppColors.warning500;  // CAUTION
    if (score <= 0.74) return const Color(0xFFF97316); // ELEVATED
    return const Color(0xFFEF4444);                  // DANGER
  }

  static Color glow(double score) {
    if (score <= 0.40) return const Color(0x3310B981);
    if (score <= 0.60) return const Color(0x33F59E0B);
    if (score <= 0.74) return const Color(0x33F97316);
    return const Color(0x4DEF4444);
  }
}
```

**Glassmorphism Spec:**

```dart
// Dark mode glass
static const glassDarkFill   = Color(0x0FFFFFFF); // rgba(255,255,255,0.06)
static const glassDarkBorder = Color(0x1AFFFFFF); // rgba(255,255,255,0.10)

// Light mode glass
static const glassLightFill   = Color(0xB3FFFFFF); // rgba(255,255,255,0.70)
static const glassLightBorder = Color(0xE6FFFFFF); // rgba(255,255,255,0.90)

// Implementation:
ClipRRect(
  borderRadius: BorderRadius.circular(AppRadius.xl),
  child: BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
    child: Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.glassDarkFill : AppColors.glassLightFill,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: isDark ? AppColors.glassDarkBorder : AppColors.glassLightBorder,
          width: 1.0,
        ),
        boxShadow: [AppShadows.medium],
      ),
      child: child,
    ),
  ),
)
// RULE: Maximum 3 BackdropFilter widgets simultaneously on screen
```

### 2.2 Typography System

```dart
// lib/core/theme/app_typography.dart
// Fonts: Inter (primary) + JetBrains Mono (data)

class AppTypography {
  static TextStyle displayXL = GoogleFonts.inter(
    fontSize: 48, fontWeight: FontWeight.w800, height: 1.1);
  static TextStyle displayL = GoogleFonts.inter(
    fontSize: 36, fontWeight: FontWeight.w700, height: 1.15);
  static TextStyle displayM = GoogleFonts.inter(
    fontSize: 28, fontWeight: FontWeight.w700, height: 1.2);
  static TextStyle headingL = GoogleFonts.inter(
    fontSize: 22, fontWeight: FontWeight.w600, height: 1.3);
  static TextStyle headingM = GoogleFonts.inter(
    fontSize: 18, fontWeight: FontWeight.w600, height: 1.35);
  static TextStyle headingS = GoogleFonts.inter(
    fontSize: 15, fontWeight: FontWeight.w600, height: 1.4);
  static TextStyle bodyL = GoogleFonts.inter(
    fontSize: 16, fontWeight: FontWeight.w400, height: 1.6);
  static TextStyle bodyM = GoogleFonts.inter(
    fontSize: 14, fontWeight: FontWeight.w400, height: 1.6);
  static TextStyle bodyS = GoogleFonts.inter(
    fontSize: 12, fontWeight: FontWeight.w400, height: 1.5);
  static TextStyle labelL = GoogleFonts.inter(
    fontSize: 14, fontWeight: FontWeight.w500, height: 1.2);
  static TextStyle labelM = GoogleFonts.inter(
    fontSize: 12, fontWeight: FontWeight.w500, height: 1.2);

  // Data display — JetBrains Mono
  static TextStyle monoDataL = GoogleFonts.jetBrainsMono(
    fontSize: 28, fontWeight: FontWeight.w700, height: 1.0);
  static TextStyle monoDataM = GoogleFonts.jetBrainsMono(
    fontSize: 20, fontWeight: FontWeight.w600, height: 1.1);
  static TextStyle monoDataS = GoogleFonts.jetBrainsMono(
    fontSize: 14, fontWeight: FontWeight.w500, height: 1.2);
}
```

### 2.3 Spacing & Radius

```dart
// lib/core/theme/app_spacing.dart
class AppSpacing {
  static const double sp1  = 4.0;
  static const double sp2  = 8.0;
  static const double sp3  = 12.0;
  static const double sp4  = 16.0;
  static const double sp5  = 20.0;
  static const double sp6  = 24.0;
  static const double sp8  = 32.0;
  static const double sp10 = 40.0;
  static const double sp12 = 48.0;
  static const double sp16 = 64.0;

  static const double screenMarginPhone  = 20.0;
  static const double screenMarginTablet = 32.0;
  static const double minTouchTarget     = 48.0;
}

// lib/core/theme/app_radius.dart
class AppRadius {
  static const double xs   = 4.0;
  static const double sm   = 8.0;
  static const double md   = 12.0;
  static const double lg   = 16.0;
  static const double xl   = 20.0;
  static const double xl2  = 24.0;
  static const double xl3  = 32.0;
  static const double full = 9999.0;
}
```

### 2.4 Elevation & Shadows

```dart
// lib/core/theme/app_shadows.dart
class AppShadows {
  static BoxShadow level1 = BoxShadow(
    color: const Color(0xFF7C3AED).withOpacity(0.08),
    blurRadius: 3, offset: const Offset(0, 1));
  static BoxShadow level2 = BoxShadow(
    color: const Color(0xFF7C3AED).withOpacity(0.12),
    blurRadius: 12, offset: const Offset(0, 4));
  static BoxShadow medium = level2;
  static BoxShadow level3 = BoxShadow(
    color: const Color(0xFF7C3AED).withOpacity(0.20),
    blurRadius: 24, offset: const Offset(0, 8));
  static BoxShadow level4 = BoxShadow(
    color: const Color(0xFF7C3AED).withOpacity(0.30),
    blurRadius: 40, offset: const Offset(0, 16));
  static BoxShadow level5 = BoxShadow(
    color: const Color(0xFF7C3AED).withOpacity(0.40),
    blurRadius: 60, offset: const Offset(0, 24));
}
```

---

## FRONTEND §3 — Animation System

### 3.1 Animation Tokens

```dart
// lib/core/animations/animation_tokens.dart
class AnimDuration {
  static const instant     = Duration.zero;
  static const micro       = Duration(milliseconds: 100);
  static const fast        = Duration(milliseconds: 150);
  static const standard    = Duration(milliseconds: 250);
  static const comfortable = Duration(milliseconds: 350);
  static const expressive  = Duration(milliseconds: 500);
  static const dramatic    = Duration(milliseconds: 800);
}

class AnimCurve {
  static const standard    = Curves.easeInOut;
  static const decelerate  = Curves.easeOut;
  static const accelerate  = Curves.easeIn;
  static const comfortable = Curves.easeInOutCubic;
  static const spring      = SpringDescription(mass: 1, stiffness: 100, damping: 10);
  static const elastic     = Curves.elasticOut;
  static const sine        = Curves.linearToEaseOut;
}

// MANDATORY: Check before every AnimationController
bool get shouldAnimate =>
  !MediaQuery.of(context).disableAnimations;
```

### 3.2 Screen Transitions

| Transition | From → To | Type | Spec |
|------------|-----------|------|------|
| Root push | Any → Child | Fade + slide up 24dp | 250ms easeInOutCubic |
| Auth flow | Login → Signup → OTP | Slide left (shared X axis) | 300ms easeInOut |
| Onboarding pages | Page N → N+1 | Parallax (content 100%, BG 15%) | 350ms spring |
| Home → Emergency | Home → SOS | Scale + blur from FAB origin | 500ms spring |
| Home → Monitor | Home → Live | Shared element: threat gauge | 400ms Hero widget |
| Dashboard cards | Card → Detail | Container transform (Material 3) | 350ms |
| Bottom nav tabs | Tab A → Tab B | Fade-through (opacity dip 0 then rise) | 200ms |
| Modal appear | Any → Modal | Sheet up from bottom + blur overlay | 350ms spring(0.8) |
| Back gesture | Child → Parent | Predictive back (Android 13+) | Follows finger |

### 3.3 Micro-Interaction Specs

**Button Interactions:**

```dart
// Primary CTA
idle:     violet gradient; elevation 2
pressed:  scale 0.96; elevation 0; 100ms easeOut
release:  spring to 1.02 then 1.0; 150ms elasticOut
loading:  label fades → 20dp spinner; 150ms crossfade
disabled: opacity 0.40; no interaction

// SOS Button
idle:     coral fill; 3 concentric rings rotating slowly
press:    scale 0.92; rings accelerate; haptic heavyImpact
hold:     countdown ring sweeps around perimeter
dispatch: ripple wave fills screen from center
```

**Input Field Interactions:**

```dart
focused:     border 1dp → 2dp violet; glow ring 6dp spread; 200ms easeOut
valid:       border → emerald; checkmark fades in right; 150ms
error:       shake keyframes [0, -6, +6, -4, +4, 0]dp; 300ms; coral-500
             error text slides down from 0 height; 200ms
password:    eye tap → characters crossfade reveal; 150ms
OTP paste:   digits fill sequentially; 50ms stagger per box
```

**Threat Gauge Animation:**

```dart
// Idle
needle oscillates ±2° at 2s period:
  Tween<double>(begin: -2, end: 2)
  CurvedAnimation(parent: _repeat, curve: Curves.easeInOut)

// Score update
SpringSimulation(
  SpringDescription(mass: 1, stiffness: 180, damping: 12),
  currentAngle,
  targetAngle,
  0.0,
)

// DANGER state entry
// 4 rapid screen edge pulses: 100ms each; heavy haptic series
// Ring colour transition: 600ms ColorTween
// Background tint: 800ms FadeTransition
```

### 3.4 Animation Package Stack

| Package | Version | Purpose | Key API |
|---------|---------|---------|---------|
| flutter_animate | ^4.5.0 | Declarative chained animations | `.animate().fadeIn().slideY().scale()` |
| rive | ^0.13.2 | State-machine animations (Splash, SOS, onboarding) | `RiveAnimation.asset()` + `StateMachineController` |
| lottie | ^3.1.0 | JSON animations (empty states, loading, success) | `Lottie.asset()` with `AnimationController` |
| animations (pub) | ^2.0.11 | Material motion patterns | `OpenContainer`, `SharedAxisTransition`, `FadeThroughTransition` |
| Built-in physics | Flutter SDK | Spring simulations for gauge, swipe, gesture | `SpringSimulation`, `FrictionSimulation` |

---

## ═══════════════════════════════════════════════════════════
## PART 3 — CLAUDE CODE EXECUTION PLAN
## ═══════════════════════════════════════════════════════════

---

## PHASE 0 — Project Bootstrap

### Task 0.1 — Create Flutter Project

```bash
# Run these commands in sequence; stop if any fails
flutter create safeher_app \
  --org io.safeher \
  --platforms android,ios \
  --template app

cd safeher_app

# Verify Flutter version
flutter --version
# Required: Flutter 3.22.0+ / Dart 3.4.0+

# Remove default template files
rm lib/main.dart
rm test/widget_test.dart
```

### Task 0.2 — Configure pubspec.yaml

```bash
cat > pubspec.yaml << 'PUBSPEC'
name: safeher_app
description: AI-Powered Wearable Safety Ecosystem for Women
version: 1.0.0+1
publish_to: none

environment:
  sdk: ">=3.4.0 <4.0.0"
  flutter: ">=3.22.0"

dependencies:
  flutter:
    sdk: flutter

  # State + Navigation
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.5
  go_router: ^13.2.0
  get_it: ^7.6.7
  injectable: ^2.3.2

  # Network
  dio: ^5.4.3
  mqtt_client: ^10.0.0
  web_socket_channel: ^2.4.0

  # Storage
  hive_flutter: ^1.1.0
  flutter_secure_storage: ^9.0.0

  # Firebase
  firebase_core: ^3.1.0
  firebase_auth: ^5.1.0
  firebase_messaging: ^15.0.0
  cloud_firestore: ^5.1.0

  # UI + Animation
  flutter_animate: ^4.5.0
  rive: ^0.13.2
  lottie: ^3.1.0
  animations: ^2.0.11
  google_fonts: ^6.2.1

  # Maps + Location
  google_maps_flutter: ^2.7.0
  geolocator: ^11.0.0
  geocoding: ^3.0.0

  # Camera + Audio
  camera: ^0.11.0
  record: ^5.1.2
  chewie: ^1.7.0

  # Charts
  fl_chart: ^0.68.0

  # BLE
  flutter_blue_plus: ^1.31.0

  # Utils
  intl: ^0.19.0
  timeago: ^3.6.0
  freezed_annotation: ^2.4.1
  json_annotation: ^4.9.0
  image_picker: ^1.1.0
  path_provider: ^2.1.3
  connectivity_plus: ^6.0.3
  permission_handler: ^11.3.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  riverpod_generator: ^2.4.0
  build_runner: ^2.4.9
  freezed: ^2.5.2
  json_serializable: ^6.8.0
  injectable_generator: ^2.4.3
  golden_toolkit: ^0.15.0
  mockito: ^5.4.4
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/rive/
    - assets/lottie/
    - assets/icons/
    - assets/images/
PUBSPEC

# Install dependencies
flutter pub get

# Verify no conflicts
flutter pub deps
```

### Task 0.3 — Create Directory Structure

```bash
# Create full directory tree
mkdir -p lib/core/theme
mkdir -p lib/core/animations
mkdir -p lib/core/router
mkdir -p lib/core/di
mkdir -p lib/core/config
mkdir -p lib/shared/components/buttons
mkdir -p lib/shared/components/cards
mkdir -p lib/shared/components/inputs
mkdir -p lib/shared/components/charts
mkdir -p lib/shared/components/overlays
mkdir -p lib/shared/components/feedback

# Feature directories
for feature in auth home monitoring emergency devices dashboard reports search profile settings; do
  mkdir -p lib/features/$feature/data
  mkdir -p lib/features/$feature/domain/models
  mkdir -p lib/features/$feature/presentation
  mkdir -p test/features/$feature
done

mkdir -p test/components
mkdir -p assets/rive
mkdir -p assets/lottie
mkdir -p assets/icons
mkdir -p assets/images

# Verify structure
find lib -type d | sort
```

### Task 0.4 — Create main.dart

```bash
cat > lib/main.dart << 'DART'
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // System UI configuration
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialise services
  await Firebase.initializeApp();
  await Hive.initFlutter();
  configureDependencies();

  runApp(
    const ProviderScope(
      child: SafeHerApp(),
    ),
  );
}

class SafeHerApp extends ConsumerWidget {
  const SafeHerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'SafeHer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
DART

# Verify it parses
dart analyze lib/main.dart 2>&1 || true
```

**Verification 0:**

```bash
flutter analyze
# Expected: "No issues found!"
# If issues: fix all before proceeding
```

---

## PHASE 1 — Design System

### Task 1.1 — app_colors.dart

```bash
cat > lib/core/theme/app_colors.dart << 'DART'
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Primary — Deep Violet Scale ─────────────────────────────────
  static const violet50  = Color(0xFFF5F3FF);
  static const violet100 = Color(0xFFEDE9FE);
  static const violet200 = Color(0xFFDDD6FE);
  static const violet400 = Color(0xFFA78BFA);
  static const violet500 = Color(0xFF8B5CF6);
  static const violet600 = Color(0xFF7C3AED); // PRIMARY BRAND
  static const violet700 = Color(0xFF6D28D9);
  static const violet800 = Color(0xFF5B21B6);
  static const violet900 = Color(0xFF4C1D95);
  static const violet950 = Color(0xFF2E1065);

  // ── Accent — Soft Coral Scale ───────────────────────────────────
  static const coral400 = Color(0xFFFF8A80);
  static const coral500 = Color(0xFFFF6B6B); // SOS + critical
  static const coral600 = Color(0xFFE53935);
  static const coral700 = Color(0xFFC62828);

  // ── Semantic ────────────────────────────────────────────────────
  static const success500 = Color(0xFF10B981);
  static const success900 = Color(0xFF064E3B);
  static const warning500 = Color(0xFFF59E0B);
  static const warning900 = Color(0xFF78350F);
  static const elevated500 = Color(0xFFF97316);
  static const danger500 = Color(0xFFEF4444);
  static const info500   = Color(0xFF3B82F6);

  // ── Dark Mode Backgrounds ───────────────────────────────────────
  static const dark900 = Color(0xFF0A0A0F);
  static const dark800 = Color(0xFF12121A);
  static const dark700 = Color(0xFF1C1C28);
  static const dark600 = Color(0xFF252535);

  // ── Light Mode Backgrounds ──────────────────────────────────────
  static const light50  = Color(0xFFF9FAFB);
  static const light100 = Color(0xFFF3F4F6);
  static const light200 = Color(0xFFE5E7EB);

  // ── Text ────────────────────────────────────────────────────────
  static const textDarkPrimary   = Color(0xFFFFFFFF);
  static const textDarkSecondary = Color(0xFFB0B0C3);
  static const textDarkTertiary  = Color(0xFF6B6B80);
  static const textLightPrimary  = Color(0xFF111827);
  static const textLightSecondary= Color(0xFF374151);
  static const textLightTertiary = Color(0xFF6B7280);

  // ── Glassmorphism ───────────────────────────────────────────────
  static const glassDarkFill    = Color(0x0FFFFFFF);
  static const glassDarkBorder  = Color(0x1AFFFFFF);
  static const glassLightFill   = Color(0xB3FFFFFF);
  static const glassLightBorder = Color(0xE6FFFFFF);

  // ── Threat State System ─────────────────────────────────────────
  static Color threatFill(double score) {
    if (score <= 0.40) return success500;
    if (score <= 0.60) return warning500;
    if (score <= 0.74) return elevated500;
    return danger500;
  }

  static Color threatGlow(double score) {
    if (score <= 0.40) return success500.withOpacity(0.20);
    if (score <= 0.60) return warning500.withOpacity(0.20);
    if (score <= 0.74) return elevated500.withOpacity(0.20);
    return danger500.withOpacity(0.30);
  }

  static Color threatBackground(double score) {
    if (score <= 0.40) return success500.withOpacity(0.05);
    if (score <= 0.60) return warning500.withOpacity(0.05);
    if (score <= 0.74) return elevated500.withOpacity(0.05);
    return danger500.withOpacity(0.08);
  }

  static String threatLabel(double score) {
    if (score <= 0.40) return 'SAFE';
    if (score <= 0.60) return 'CAUTION';
    if (score <= 0.74) return 'ELEVATED';
    return 'DANGER';
  }
}
DART
```

### Task 1.2 — Remaining Theme Files

Create in sequence, verifying each compiles:

```bash
# app_typography.dart, app_spacing.dart, app_radius.dart,
# app_shadows.dart, animation_tokens.dart, app_theme.dart
# theme_extensions.dart
#
# Each file must:
#   - Have no import errors
#   - Use only the packages already in pubspec.yaml
#   - Expose all tokens as static const where possible
#   - Support both dark and light theme contexts

# After creating all theme files, verify:
flutter analyze lib/core/
# Expected: 0 issues
```

### Task 1.3 — Theme Preview Screen

```bash
# Create lib/core/theme/theme_preview_screen.dart
# This screen shows ALL design tokens visually
# It must NOT appear in production (flavor-gated)
# Run it to verify visual correctness before building components

flutter run -t lib/core/theme/theme_preview_screen.dart
# Manually verify: all colours visible, typography readable,
# glass effect working in both dark and light mode
```

**Verification 1:**

```bash
flutter analyze lib/core/
flutter test test/theme/                  # token unit tests
# Expected: 0 issues; all tests pass
git add -A && git commit -m "feat: design system complete"
git tag v0.1.0
```

---

## PHASE 2 — Component Library

Build every component in this order. Each component requires:
1. The widget file
2. A widget test file
3. A golden test

```bash
# Component build order:
# (Stop and fix if any component test fails before proceeding)

# 1. SaButton (6 variants)
# 2. SaTextField + SaPasswordField + SaOTPField
# 3. SaCard (base glass card)
# 4. SaStatusDot + SaBatteryBar + SaSignalBars
# 5. SaThreatChip
# 6. SaThreatGauge (CustomPainter — most complex component)
# 7. SaWaveform (CustomPainter — real-time audio)
# 8. SaMotionChart (CustomPainter — 3-axis sparkline)
# 9. SaDonutChart (CustomPainter)
# 10. SaSparkline (fl_chart)
# 11. SaBarChart (fl_chart)
# 12. SaBottomSheet + SaDialog + SaToast
# 13. SaEmptyState (Lottie)
# 14. SaLoadingShimmer
# 15. SaProgressRing
# 16. SaBottomNavBar (animated floating pill)
# 17. SaDeviceCard + SaAlertCard + SaContactCard + SaStatCard
```

### Component Spec: SaButton

```dart
// lib/shared/components/buttons/sa_button.dart

enum SaButtonVariant { primary, secondary, ghost, danger, icon, sos }
enum SaButtonSize    { sm, md, lg }

class SaButton extends StatefulWidget {
  const SaButton({
    super.key,
    required this.label,
    required this.onTap,
    this.variant = SaButtonVariant.primary,
    this.size = SaButtonSize.md,
    this.isLoading = false,
    this.isFullWidth = false,
    this.icon,
    this.confirmRequired = false, // for danger variant
  });

  // Implementation requirements:
  // Press: GestureDetector onTapDown → scale 0.96; 100ms easeOut
  // Release: spring back 1.02 → 1.0; 150ms elasticOut
  // Loading: AnimatedSwitcher label ↔ spinner; 150ms crossfade
  // Disabled: opacity 0.40; gesture disabled
  // Semantics: label, button: true, enabled: !isLoading
  // RepaintBoundary: wraps the entire button
}
```

### Component Spec: SaThreatGauge (CustomPainter)

```dart
// lib/shared/components/charts/sa_threat_gauge.dart
// This is the most important visual component in the app

class SaThreatGaugePainter extends CustomPainter {
  // Draws:
  // 1. Background track arc: 0° to 270° (135° start)
  // 2. Four coloured zone arcs (SAFE/CAUTION/ELEVATED/DANGER)
  // 3. Animated needle from center: spring physics
  // 4. Center score text: JetBrains Mono; digit-roll animation
  // 5. Threat state label below score

  // Animation:
  // needleAngle: SpringSimulation updates via AnimationController
  // scoreDigit: AnimatedFlipCounter or custom Tween<int>
  // colourTransition: ColorTween on threat state change
  // glowPulse: scale 1.0→1.04 at DANGER; Curves.easeInOut repeat

  // Performance:
  // shouldRepaint: only when score or colour changes
  // Entire widget in RepaintBoundary
  // No setState: all animation via AnimationController notify
}
```

### Component Spec: SaBottomNavBar

```dart
// lib/shared/components/sa_bottom_nav_bar.dart
// Floating pill nav — NOT a standard BottomNavigationBar

// Layout:
// Glass pill; height 64dp; horizontal padding 24dp; radius full
// Positioned above system nav with 16dp offset
// 4 tabs (Home/Monitor/Dashboard/Profile) + 1 centre SOS FAB

// Tab animation:
// Active: scale 1.0→1.15; label fades in (150ms); indicator dot appears
// Inactive: opacity 0.50; no label
// Indicator dot: 6dp circle; AnimatedPositioned slides between tabs
// Tab switch: FadeTransition (fade-through); 200ms

// SOS FAB:
// Coral circle 56dp; floats 12dp ABOVE nav surface
// RiveAnimation for breathing idle state
// Tap: Hero morph transition to Emergency screen

// Hide/show on scroll:
// AnimatedSlide: translateY(+80dp) on scroll down; 200ms easeIn
// AnimatedSlide: translateY(0) on scroll up or tap; 200ms spring
// Always visible on: /, /emergency, /profile routes

// Haptic:
// HapticFeedback.selectionClick() on every tab change
```

**Verification 2:**

```bash
flutter analyze lib/shared/
flutter test test/components/ --coverage
# Expected: 0 issues; coverage > 80% on component files
# Run golden tests:
flutter test test/components/ --update-goldens  # first time only
flutter test test/components/                   # subsequent runs
git add -A && git commit -m "feat: component library complete"
git tag v0.2.0
```

---

## PHASE 3 — GoRouter Configuration

```bash
cat > lib/core/router/app_router.dart << 'DART'
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

// Route constants
class AppRoutes {
  static const splash            = '/';
  static const onboarding        = '/onboarding';
  static const login             = '/auth/login';
  static const signup            = '/auth/signup';
  static const otp               = '/auth/otp';
  static const forgot            = '/auth/forgot';
  static const home              = '/home';
  static const monitor           = '/monitor';
  static const dashboard         = '/dashboard';
  static const search            = '/search';
  static const profile           = '/profile';
  static const deviceDetail      = '/devices/:id';
  static const emergency         = '/emergency';
  static const reportList        = '/reports';
  static const reportDetail      = '/reports/:id';
  static const settings          = '/settings';
  static const emergencyContacts = '/settings/contacts';
}

@riverpod
GoRouter appRouter(AppRouterRef ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    redirect: (context, state) {
      final isAuthenticated = authState.valueOrNull != null;
      final isOnAuthRoute = state.matchedLocation.startsWith('/auth')
          || state.matchedLocation == '/'
          || state.matchedLocation == '/onboarding';

      if (!isAuthenticated && !isOnAuthRoute) {
        return AppRoutes.login;
      }
      if (isAuthenticated && isOnAuthRoute
          && state.matchedLocation != '/') {
        return AppRoutes.home;
      }
      return null;
    },
    routes: [
      // Add all routes here with their screen widgets
      // Each route must use the correct transition defined in §3.2
    ],
  );
}
DART
```

---

## PHASE 4 — Screens (Build in Strict Order)

### Screen Build Protocol

For EACH screen, follow this exact micro-loop:

```bash
# 1. Create screen file
# 2. Create provider file
# 3. Wire GoRouter route
# 4. flutter run → verify: no red screen; no exceptions in console
# 5. flutter test test/features/{feature}/ → all pass
# 6. golden test → capture golden
# 7. git commit -m "feat({screen}): screen complete"
```

---

### SCREEN 1 — Splash (`/`)

**File:** `lib/features/auth/presentation/splash_screen.dart`

**Spec:**

```
Duration: ≤ 1.8 seconds total
Background: AppColors.dark900 — full bleed

Animation sequence (use Rive "SplashSM" OR flutter_animate chain):
  0ms:      Screen appears with dark-900 background
  0–300ms:  SafeHer shield SVG: scale 0.6→1.0, opacity 0→1
            Violet glow ring: radius 0→80dp; opacity 0→0.6
  300–700ms: Shield fill sweeps upward (ClipRect animation)
  700–1000ms: "SAFEHER" wordmark: opacity 0→1; translateY +12→0
  1000–1200ms: Tagline fades in 200ms after wordmark
  1200–1500ms: Glow pulse — ring 80→120dp; opacity 0.6→0
  1500–1800ms: Entire screen fades out OR direct route transition

Auth check: runs during animation via FutureProvider
On complete: GoRouter redirects:
  → /onboarding if first_launch (Hive flag: onboarding_seen = false)
  → /home if authenticated
  → /auth/login if not authenticated
```

**Widget test requirements:**

```dart
testWidgets('renders without exception', ...);
testWidgets('navigates after animation completes', ...);
goldenTest('golden_splash_dark', ...);
```

---

### SCREEN 2 — Onboarding (`/onboarding`)

**File:** `lib/features/auth/presentation/onboarding_screen.dart`

**Spec:**

```
PageView controller; 3 pages; BouncingScrollPhysics
Page indicator: 3 dots; active → pill (24dp wide); spring 200ms

Page 1 "Always Protected":
  Background: radial gradient(violet-950 centre, dark-900 edge)
  Illustration: RiveAnimation.asset('assets/rive/onboarding_1.riv')
                state: "IdleAnimate" trigger on page active
  Title: "Always Protected" — displayXL, violet-600
  Body: "SafeHer watches over you silently, every step of the way."
  (no CTA on page 1)

Page 2 "AI That Understands":
  Background: radial gradient(indigo-900 centre, dark-900 edge)
  Illustration: Lottie.asset('assets/lottie/neural_shield.json')
  Title: "AI That Understands"
  Body: "Motion, sound, and vision working together to keep you safe."

Page 3 "Help in Seconds":
  Background: radial gradient(coral-900 centre, dark-900 edge)
  Illustration: RiveAnimation.asset('assets/rive/onboarding_3.riv')
  Title: "Help in Seconds"
  Body: "One tap. Your trusted people know exactly where you are."
  CTA: SaButton(label: 'Get Started', size: lg, fullWidth: true)
       Animates: slideY(+20dp → 0) when page 3 becomes active; 350ms spring
       onTap: save onboarding_seen=true in Hive; GoRouter.go('/auth/login')

Parallax implementation:
  PageController.page stream → compute offset for each element
  Illustrations: offset * 0.30 (slower)
  Text: offset * 1.00 (normal speed)
  Background: offset * 0.15 (slowest = deep parallax)

Skip button: Positioned top-right; ghost LabelM
  Visible on pages 0 and 1 only
  onTap: same as "Get Started"
```

---

### SCREEN 3 — Login (`/auth/login`)

**File:** `lib/features/auth/presentation/login_screen.dart`

**Spec:**

```
Layout: SafeArea → SingleChildScrollView → Padding(20dp horizontal)
Background: dark-900 + RadialGradient(violet-950, transparent, center top)
Keyboard: resizeToAvoidBottomInset: true
Scroll: auto-scrolls to ensure focused field visible + 20dp padding

Enter animation (flutter_animate chain, stagger):
  Logo: fadeIn(300ms)
  Headline: fadeIn + slideY(-16→0); 350ms; 100ms delay
  Each field: fadeIn + slideY; 50ms stagger between elements

Elements (top → bottom):
  1. SafeHerLogo widget: shield SVG 48dp + "SAFEHER" wordmark
  2. Text "Welcome back" — displayM, textDarkPrimary
  3. Text "Sign in to your safe space" — bodyL, textDarkSecondary
  4. SaTextField(label: 'Email address', keyboardType: emailAddress)
     suffix: clear IconButton (visible when value.isNotEmpty)
  5. SaPasswordField(label: 'Password')
     suffix: eye toggle + TextButton('Forgot?') — tap → /auth/forgot
  6. SaButton(label: 'Sign In', variant: primary, size: lg, fullWidth: true)
     isLoading: true during auth call
  7. Divider row: Row[Expanded(Divider), Text('or continue with'), Expanded]
  8. SocialLoginButton(provider: google): white card; Google SVG; 54dp
  9. SocialLoginButton(provider: apple): iOS only; Platform.isIOS check
  10. Row[ Text('New here? '), TextButton('Create account') ]
      TextButton → GoRouter.go('/auth/signup')

Validation (Formz or custom):
  Empty email: field.shake() + 'Email is required' slideDown
  Invalid format: 'Enter a valid email address'
  Wrong credentials: SaToast.show(context, 'Incorrect email or password',
                     variant: error)
  Network error: SaToast.show(context, 'Connection failed. Try again.',
                 variant: error)
```

---

### SCREEN 4 — Signup (`/auth/signup`)

**File:** `lib/features/auth/presentation/signup_screen.dart`

**Spec:**

```
Layout: Same as Login; keyboard-aware scroll

Fields (top → bottom):
  Row: [
    SaTextField(label: 'First Name', flex: 1),
    SizedBox(width: 12),
    SaTextField(label: 'Last Name', flex: 1),
  ]
  SaTextField(label: 'Email address')
  SaPhoneField(label: 'Phone number')  ← country code picker + E.164
  SaPasswordField(label: 'Password') + PasswordStrengthBar (4 segments):
    < 8 chars: 1 red segment
    8+ no special: 2 orange segments
    8+ with special: 3 yellow segments
    12+ mixed + special: 4 green segments + animated checkmark right
  SaTextField(label: 'Confirm password')
    suffix: real-time match indicator (✗ coral → ✓ emerald as typed)

CTA: SaButton(label: 'Create Account', variant: primary, size: lg, fullWidth: true)
  Disabled (0.40 opacity, gesture disabled) until all fields pass validation
  On tap: validate left-to-right; first invalid field: shake + focus

Terms: Text.rich at bottom:
  "By continuing you agree to our "
  TextSpan('Terms of Service', violet-500, tap → terms URL)
  " and "
  TextSpan('Privacy Policy', violet-500, tap → privacy URL)
```

---

### SCREEN 5 — OTP Verification (`/auth/otp`)

**File:** `lib/features/auth/presentation/otp_screen.dart`

**Spec:**

```
6 individual OtpDigitBox widgets in a Row
Each box: width 44dp; height 56dp; gap 8dp; radius md(12dp)
Border: 1dp neutral → 2dp violet on focus; 1dp emerald on valid

OtpController (custom):
  Manages 6 FocusNode + 6 TextEditingController
  onDigitEntered: border fills violet; auto-advance; 80ms spring
  onBackspace: clear current + retreat to previous
  onPaste(String text): validate 6 digits; fill sequentially;
                        each box fills with 50ms stagger

Wrong OTP:
  All 6 boxes shake simultaneously: [-6, +6, -4, +4, 0]dp; 300ms
  All boxes flash coral border
  All boxes clear
  'Invalid code. Try again.' text fades in below

Correct OTP:
  All boxes transition to emerald border: 150ms
  Animated checkmark draws in (CustomPainter stroke anim): 400ms
  Navigate to /home or next step: 200ms delay

Resend section:
  CountdownTimer: 60 seconds; displays "Resend in {n}s" in bodyS
  At 0: 'Resend OTP' TextButton activates; onTap: restart timer;
        call resend API; SaToast.show('OTP sent!', variant: success)
```

---

### SCREEN 6 — Home (`/home`)

**File:** `lib/features/home/presentation/home_screen.dart`

**Spec:**

```
Root: Scaffold → Stack:
  [0] CustomScrollView (main content)
  [1] SOS FAB (positioned above BottomNavBar)

AppBar: SliverAppBar(floating: true, snap: true)
  Background: transparent → dark-800 blur as scrollProgress 0→1
  AnimatedOpacity on scroll: threshold 100dp

SECTION 1 — Greeting (SliverToBoxAdapter)
  Parallax: scroll offset × 0.5 via ScrollNotification
  Row: [
    CircleAvatar(radius: 20, violet border 2dp, tap → /profile),
    Expanded(Text('Good ${_timeGreeting()}, ${user.firstName}',
             style: headingL)),
    NotificationBell(hasBadge: unreadCount > 0),
  ]
  Subtext: Row[ Text(DateFormat('EEEE, d MMM'), bodyS),
               SaStatusDot(status: online), Text('Monitoring Active') ]
  NotificationBell: badge dot (coral-500); pulses via flutter_animate
                   when unreadCount > 0

SECTION 2 — Threat Status Card (SliverToBoxAdapter)
  Hero(tag: 'threat_gauge', child: SaThreatGaugeCard())
  Full-width glass card; radius-2xl; margin 20dp horizontal
  SaThreatGaugeCard layout:
    Left 60%: SaThreatGauge (CustomPainter; height 160dp)
    Right 40%: Column of 3 SaMiniScoreChips (Motion/Audio/Vision)
    Bottom: Text('Updated ${timeago.format(lastUpdate)}', monoDataS)
  Data: ref.watch(threatScoreStreamProvider)

SECTION 3 — Device Status (SliverToBoxAdapter)
  Text('Devices', headingM) — section label
  SizedBox(height: 120) → ListView.separated horizontal:
    SaDeviceCard per paired device (width: 140dp)
    Trailing: 'Pair Device' card (dashed border; "+"; tap → BLE scan)

SECTION 4 — Quick Actions (SliverToBoxAdapter)
  Text('Quick Actions', headingM)
  GridView.count(crossAxisCount: 2, mainAxisSpacing: 12,
                 crossAxisSpacing: 12):
    SaQuickActionCard(icon, label, onTap) for:
      ('SOS', coral tint, → /emergency)
      ('Call Contact', → call priority 1 contact)
      ('Share Location', → start live location share)
      ('Record', → open camera + audio recorder)

SECTION 5 — Live Monitor Preview (SliverToBoxAdapter)
  Glass card; Row:
    Column left: mini SaWaveform (height: 48, barCount: 32)
                 Caption: 'Audio'
    VerticalDivider
    Column right: mini SaMotionChart (height: 48, axis: 'z')
                  Caption: 'Motion'
  TextButton('View Live Feed →', violet-500)
     onTap: GoRouter.go('/monitor')

SECTION 6 — Recent Alerts (SliverToBoxAdapter)
  Text('Recent Alerts', headingM)
  ref.watch(recentAlertsProvider).when(
    data: (alerts) => Column(
      children: alerts.take(3).map((a) => SaAlertCard(alert: a)).toList()
    ),
    loading: () => Column(children: List.generate(3,
      (_) => SaLoadingShimmer(height: 72))),
    error: (e, _) => SaEmptyState(message: 'Could not load alerts'),
  )
  TextButton('View all reports →') → /reports

SECTION 7 — Daily Safety Score (SliverToBoxAdapter)
  SaStatCard(value: '${safetyScore}', label: 'Daily Safety Score',
             subValue: '${streakDays} day streak', icon: Icons.shield)

SOS Emergency FAB:
  Positioned(bottom: 88dp, right: 20dp)  ← above bottom nav
  FloatingActionButton.extended:
    backgroundColor: coral-500
    icon: SvgPicture.asset('assets/icons/shield.svg', width: 20)
    label: Text('SOS', displayM-ish, white)
  Idle animation: scale 1.0→1.04→1.0 sinusoidal at 3s period
  onPressed: GoRouter.go('/emergency')  ← Hero morph transition
```

---

### SCREEN 7 — Device Management (`/devices`)

```
CustomScrollView:
  SliverAppBar: 'My Devices' title + device count subtitle

Per device: SaDeviceCard (expanded variant)
  header: device type SVG icon + name + SaStatusDot
  battery: SaBatteryBar (animated to current %) + '~{N}h remaining'
  signal: SaSignalBars (RSSI to bars mapping)
  firmware: version mono text + chip('Up to date' emerald | 'Update Available' coral)
  sensors: 3-column Row: [Accel 9.8 m/s², Gyro 0.2°/s, Flex 75%]
           All values: monoDataS; update via MQTT stream
  onTap: AnimatedSize expand → full sensor grid + calibration CTA

3D device visual: Rive or Lottie asset per device type
  Glove fingers: driven by flex sensor values 0–100%
  Loading: SaLoadingShimmer (same card dimensions)

BLE Scan Sheet (showSaBottomSheet):
  Animated radar rings: CustomPainter 3 concentric; scale pulse
  Found devices ListView:
    Device name + RSSI SaSignalBars + SaButton('Pair', sm)
  Pairing: SaDialog(title: 'Enter PIN', body: SaOTPField(length: 6))
```

---

### SCREEN 8 — Live Monitoring (`/monitor`)

```
Stack (fills entire screen — no scroll):
  [0] Background gradient dark-900
  [1] SafeArea → Column children below

Panel 1 — Threat Gauge (Hero from Home 'threat_gauge'):
  Hero(tag: 'threat_gauge', child: SaThreatGaugeCard(large: true))
  large variant: gauge height 200dp; fills top 40% of screen

Panel 2 — Audio Waveform (RepaintBoundary mandatory):
  SaWaveform(
    barCount: 64,
    data: ref.watch(audioAmplitudeStreamProvider),
    height: 80,
  )
  Below: Row[ Text('${db} dB', monoDataS), SaThreatChip(emotionClass) ]
  Updates: Timer.periodic(33ms) → ~30fps tick → notifyListeners()

Panel 3 — Motion Timeline (RepaintBoundary mandatory):
  SaMotionChart(
    data: ref.watch(motionTimelineProvider), // last 60s
    axes: ['x', 'y', 'z'],
    windowSeconds: 60,
    onEventTap: (event) => _showEventTooltip(event),
  )
  Auto-scrolls right as new data arrives

Panel 4 — Camera Feed:
  if glassesPaired:
    Stack:
      Image.memory(latestFrame, fit: BoxFit.cover)  ← MJPEG frame
      CustomPaint(painter: DetectionBoxPainter(detections))
  else:
    SaEmptyState(
      lottie: 'assets/lottie/glasses_offline.json',
      title: 'Glasses not connected',
      cta: SaButton(label: 'Pair Glasses', onTap: ...),
    )

MJPEG stream implementation:
  http.Client() streaming GET to camera endpoint
  Decode on compute() isolate
  Feed Uint8List to ValueNotifier<Uint8List?>
  Image.memory() listens via ValueListenableBuilder
  RepaintBoundary wraps Image.memory
```

---

### SCREEN 9 — Dashboard (`/dashboard`)

```
CustomScrollView:
  SliverAppBar: 'Dashboard' title; collapsing

  SliverPadding:
    Column of dashboard rows (not a grid — better control):

    Row 1 (full-width):
      Card 1 — Total Incidents
        violet gradient background; large number; trend arrow; 30-day SaSparkline

    Row 2 (full-width):
      Card 2 — Threat Analytics
        SaBarChart; grouped by day; threat colour coding
        onBarTap(date): showSaBottomSheet → incident list for that day

    Row 3 (full-width):
      Card 3 — Location Heatmap
        SaHeatGrid (CustomPainter) or google_maps_flutter snapshot

    Row 4 (two halves):
      Card 4 — AI Confidence SaDonutChart (3 segments)
      Card 5 — Recent Reports list (3 items)

    Row 5 (two halves):
      Card 6 — Device Health (battery trend per device)
      Card 7 — Weekly Safety Score (circular SaProgressRing + streak)

All cards:
  Glass surface; radius-2xl; elevation-2
  Stagger appear: fadeIn + translateY(16→0); 50ms delay per card
  SaLoadingShimmer while data loads (same shape as card content)
  Data: Riverpod AsyncNotifier; revalidate on pull-to-refresh
```

---

### SCREEN 10 — Search (`/search`)

```
Entry transition: SaSearchBar slides down from AppBar position;
                  keyboard opens; 250ms easeInOut

SaSearchBar:
  radius: full; height 54dp; glass surface
  leading: AnimatedIcon(search↔mic); morphs when voice active
  trailing: AnimatedOpacity clear X (visible when text.isNotEmpty)
  autofocus: true on screen enter

Voice Search overlay (when mic tapped):
  Full-screen dark-900 overlay; FadeTransition in
  3 concentric rings: CustomPainter; pulse with mic amplitude
  SaWaveform beneath rings (real-time mic input)
  Text: 'Listening...' bodyL pulsing opacity
  X button top-right to cancel

Empty state (searchQuery.isEmpty):
  Section 'Recent Searches': Wrap of ghost chips; tap fills search bar
  Section 'Quick Access': GridView 2×2:
    [Reports icon card, Contacts icon card,
     Devices icon card, Settings icon card]

Results (searchQuery.isNotEmpty):
  TabBar: All | Reports | Contacts | Devices | Settings
  Animated underline indicator (AnimatedPositioned slides)

  All tab: flat list mixing all result types
  Reports tab: SaIncidentCard list
  Contacts tab: SaContactCard list + 'Alert' quick action button
  Devices tab: SaDeviceCard compact list
  Settings tab: Icon + name + current value; tap → navigate directly

  No results: SaEmptyState(lottie: 'no_results.json',
               title: 'No results for "$query"',
               subtitle: 'Try a different search term')
```

---

### SCREEN 11 — EMERGENCY (`/emergency`) — MOST CRITICAL

```
Entry: Hero transition from SOS FAB
       morphs FAB coral circle → full-screen layout
Background: dark-900 + RadialGradient(coral-500 opacity 0.15, center)

═══════════════════════════════════════════════
STAGE 1 — PRE-ACTIVATION (isTriggered = false)
═══════════════════════════════════════════════

Center (Positioned.fill → Center):
  Stack alignment: center children:

  // Ring 3 (outermost; 280dp)
  AnimatedBuilder(animation: _ring3Controller,
    builder: (_, __) => Container(
      width: 280 + (_ring3Scale.value * 20),
      height: 280 + (_ring3Scale.value * 20),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.coral500.withOpacity(0.08 * _ring3Opacity.value),
      ),
    )
  ) // Scale 1.0→1.08 at 2s period; counter-rotate slowly

  // Ring 2 (240dp): coral 15% opacity; rotation animation
  // Ring 1 (200dp): coral 30% opacity; faster rotation

  // SOS Button (160dp)
  GestureDetector(
    onLongPressStart: (_) => _startCountdown(),
    onLongPressEnd: (_) => _cancelIfNotConfirmed(),
    child: AnimatedContainer(
      width: 160, height: 160,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient([coral600, coral500]),
        boxShadow: [BoxShadow(coral500, 0, 0, 40, 0.5)], // glow
      ),
      duration: 100ms,
      child: Column(center: [
        SvgPicture('shield.svg', width: 32, color: white),
        Text('SOS', displayL, white),
      ]),
    ),
  )

Above button: Text('Hold to confirm', bodyM, coral-200)
Below button: SaButton(label: 'Cancel', variant: ghost, size: md)
              → GoRouter.pop()

═══════════════════════════════════════════════
STAGE 2 — COUNTDOWN (countdownSeconds = 10→0)
═══════════════════════════════════════════════

CountdownRing: CustomPainter stroke sweeping coral around 160dp button
  Duration: (countdownSeconds * 1000)ms; linear

Center: animated digit counter
  AnimatedSwitcher(
    duration: 200ms,
    transitionBuilder: (child, anim) => ScaleTransition(
      scale: anim, child: child),
    child: Text('$countdown', key: ValueKey(countdown), monoDataL),
  )

Text below counter: '$countdown seconds' — pulses opacity each tick
GPS display: fades in below button
  Text('${lat.toFixed(6)}, ${lng.toFixed(6)}', monoDataS, coral-200)
  SaStatusDot(online) + Text('GPS locked')

Cancel button: SaButton(label: 'Cancel Alert', variant: ghost,
               size: lg, fullWidth: true, borderColor: coral-500)
  onTap: _cancelCountdown(); HapticFeedback.selectionClick()

Haptic: HapticFeedback.lightImpact() each countdown tick

═══════════════════════════════════════════════
STAGE 3 — ALERT DISPATCHED
═══════════════════════════════════════════════

On dispatch:
  1. HapticFeedback.heavyImpact() × 3; 200ms apart
  2. Coral ripple CustomPainter: radius 0 → screen diagonal; 600ms
  3. Transition to confirmation layout (AnimatedSwitcher 400ms)

Confirmation layout:
  Lottie or CustomPainter: emerald checkmark draws itself; 600ms
  Text('Alert Sent', displayM, white)
  Text('Notifying $contactCount contacts...', bodyL, coral-200)

  AnimatedList: contacts appear one-by-one; 200ms stagger
    Each: Row[
      CircleAvatar(initial, violet border),
      Text(contact.name, headingS),
      SaStatusDot animating → check when notified
    ]

  SaCard(glass):
    Row[ SvgPicture('gps'), Text('Live Location Shared') ]
    Text('$lat, $lng', monoDataS)
    BlinkingDot + Text('LIVE', labelM, coral-500)

  SaCard(glass):
    Row[ SvgPicture('record'), Text('Recording Evidence') ]
    LinearProgressIndicator(value: uploadProgress, coral)
    Text('${(uploadProgress * 100).toInt()}% uploaded', bodyS)

  SaButton(
    label: "I'm Safe — Cancel Alert",
    variant: primary with emerald gradient,
    size: lg, fullWidth: true,
    onTap: _showCancelConfirmation,
  )

═══════════════════════════════════════════════
STAGE 4 — CANCELLATION CONFIRMATION
═══════════════════════════════════════════════

SaConfirmDialog(
  title: "Cancel emergency alert?",
  body: "Your contacts will be notified the alert was cancelled.",
  confirmLabel: "Yes, I'm safe",
  cancelLabel: "Keep alert active",
  autoDismissAfter: Duration(seconds: 5),
  onConfirm: () {
    ref.read(emergencyProvider.notifier).cancelAlert(alertId);
    SaToast.show(context, 'Alert cancelled. Your contacts are notified.',
                 variant: success);
    GoRouter.go('/home');
  },
)
```

---

### SCREEN 12 — Reports (`/reports` + `/reports/:id`)

```
/reports — Report List:
  CustomScrollView + SliverAppBar('Reports')
  SliverList: SaIncidentCard per incident; newest first
    Left border (4dp solid): ThreatColors.fill(incident.maxScore)
    Content: [threat chip] + [date monoDataS] + [trigger type chip]
             + [ai_summary first sentence, bodyM, maxLines: 2]
    onTap: GoRouter.go('/reports/${incident.id}')
           transition: OpenContainer (Material motion)

/reports/:id — Report Detail:
  CustomScrollView:

  Section 1 — AI Summary:
    SaCard(glass):
      Row[ Lottie('ai_sparkle.json', width: 24), Text('AI Summary', headingM) ]
      Text(incident.aiSummary, bodyL)
      Text('Generated by SafeHer AI', bodyS italic, textTertiary)
      SaBarChart(
        data: [incident.motionScore, incident.audioScore, incident.visionScore],
        labels: ['Motion', 'Audio', 'Vision'],
        height: 80,
      )

  Section 2 — Event Timeline:
    TimelineWidget: vertical line; nodes at each event
    Node types:
      sensor_event → IMU icon (violet)
      ai_detection → brain icon (violet)
      alert_trigger → shield icon (coral)
      evidence_captured → camera icon (teal)
      contact_notified → person-check icon (emerald)
    Each node:
      [icon circle] — [vertical line] — [event card]:
        Text(event.title, headingS)
        Text(DateFormat.Hms.format(event.ts), monoDataS)
        Text(event.description, bodyM)
        if event.confidence != null: ConfidenceBar(event.confidence)
    ScrollNotification: nodes animate in on scroll-into-view;
                        100ms stagger; fadeIn + slideX(-16→0)

  Section 3 — Evidence Gallery:
    Text('Evidence', headingM)
    SizedBox(height: 120) → ListView horizontal:
      Per video: thumbnail stack + play icon; tap → SaBottomSheet(chewie)
      Per audio: SaWaveformCard(static waveform + play button)
      Per photo: ClipRRect image thumbnail; tap → Hero full-screen view

  Section 4 — GPS Breadcrumbs:
    SizedBox(height: 200) → GoogleMap(
      initialCameraPosition: incident.alertLocation,
      markers: breadcrumbs.map(numbered markers),
      polylines: {breadcrumb trail},
      myLocationEnabled: false,
    )

  Section 5 — Export Actions:
    SaButton(label: 'Export PDF', variant: secondary, icon: download)
      onTap: call /reports/:id/pdf; download file; share sheet
    SaButton(label: 'Share Secure Link', variant: ghost, icon: link)
      onTap: call /reports/:id/share; copy link to clipboard;
             SaToast('Link copied. Expires in 7 days.')
    Text('Chain of custody: ${incident.hash.substring(0,16)}...',
         monoDataS, textTertiary)
```

---

### SCREEN 13 — Profile (`/profile`)

```
CustomScrollView:
  SliverAppBar(expandedHeight: 220, flexibleSpace: FlexibleSpaceBar):
    Background: LinearGradient(violet-900, dark-800, bottom)
    Center: Column[
      GestureDetector(onTap: pickAvatar):
        CircleAvatar(radius: 40, border: 3dp violet-500)
        Positioned bottom-right: edit icon circle
      Text(user.fullName, displayM)
      SaThreatChip(label: 'Active User', variant: info)
    ]

  SliverToBoxAdapter:

  Stats Row: Row of 3 SaStatCards:
    SaStatCard(value: safeHours, label: 'Safe Hours', icon: timer)
    SaStatCard(value: incidents, label: 'Incidents', icon: warning)
    SaStatCard(value: streakDays, label: 'Day Streak', icon: flame)

  Section — Emergency Contacts (drag-to-reorder):
    Text('Emergency Contacts', headingM)
    ReorderableListView.builder:
      SaContactCard per contact:
        Leading: priority number in violet circle
        Avatar + name + relationship chip
        Trailing: drag handle icon + status dot (confirmed/pending)
      onReorder: ref.read(contactsProvider.notifier).reorder(from, to)
    Haptic: HapticFeedback.mediumImpact() on drag pick-up
    SaButton(label: '+ Add Contact', variant: ghost)
      → contact picker → OTP confirmation flow

  Section — Security:
    ListTile(title: 'Change Password', onTap: → /settings/password)
    SwitchListTile(
      title: 'Biometric Unlock',
      subtitle: Platform.isIOS ? 'Face ID' : 'Fingerprint',
      value: biometricEnabled,
      onChanged: ref.read(securityProvider.notifier).toggleBiometric,
    )
    ListTile(title: 'Active Sessions (${sessions.length})', onTap: showSessions)
    ListTile(
      title: Text('Sign Out All Devices', style: TextStyle(color: danger500)),
      onTap: () => showSaConfirmDialog(context, ...).then(signOutAll),
    )

  Section — Preferences:
    Text('Threat Threshold', headingS)
    Slider(
      value: threshold, min: 0.50, max: 0.95, divisions: 9,
      onChanged: (v) => ref.read(prefsProvider.notifier).setThreshold(v),
    )
    Row[Text('Conservative'), Spacer(), Text('Sensitive')] — bodyS

    Text('Countdown Duration', headingS)
    Row of 3 SaChips: ['5s', '10s', '15s']
      active chip: violet fill; others: ghost

    Row[ Text('Auto-Record on Alert'), Switch(value: autoRecord) ]
    Row[ Text('Dark Mode'), Switch(value: darkMode) ]

  Section — Data & Privacy:
    ListTile(title: 'Download My Data', onTap: downloadData)
    ListTile(
      title: Text('Delete Account',
                  style: TextStyle(color: danger500, fontWeight: w600)),
      onTap: () => showSaConfirmDialog(
        context,
        title: 'Delete Account',
        body: 'Type "DELETE" to confirm. Your data will be removed in 30 days.',
        requireTypedConfirmation: 'DELETE',
        confirmLabel: 'Delete my account',
        isDanger: true,
        onConfirm: ref.read(authProvider.notifier).deleteAccount,
      ),
    )
```

---

### SCREEN 14 — Settings (`/settings`)

```
Simple ListView with sections:
  Account: Profile, Emergency Contacts, Change Password
  Devices: Paired Devices, Pair New Device
  Notifications: Push, SMS, Email toggles per alert type
  AI & Safety: Threat threshold (links to /profile prefs)
  Appearance: Theme toggle, Language
  About: Version, Privacy Policy, Terms, Licenses
  Danger Zone: Sign out, Delete account
```

---

## PHASE 5 — Data Layer

### Repository Pattern

```dart
// lib/features/alert/domain/alert_repository.dart
abstract class AlertRepository {
  Future<Alert> createAlert(CreateAlertRequest request);
  Future<List<Alert>> getAlerts({int limit = 20});
  Stream<Alert> watchActiveAlert();
}

// lib/features/alert/data/alert_repository_impl.dart
@LazySingleton(as: AlertRepository, env: [Environment.prod])
class AlertRepositoryImpl implements AlertRepository {
  final Dio _dio;
  AlertRepositoryImpl(this._dio);

  @override
  Future<Alert> createAlert(CreateAlertRequest request) async {
    final response = await _dio.post('/alerts', data: request.toJson());
    return Alert.fromJson(response.data);
  }
  // ... other methods
}

// lib/features/alert/data/alert_repository_mock.dart
@LazySingleton(as: AlertRepository, env: [Environment.dev])
class MockAlertRepository implements AlertRepository {
  @override
  Future<Alert> createAlert(CreateAlertRequest request) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return Alert.fixture(); // static fixture data
  }
  // ... other methods using fixture data
}
```

### Riverpod Providers

```dart
// Real-time threat score from WebSocket
@riverpod
Stream<ThreatScoreUpdate> threatScoreStream(ThreatScoreStreamRef ref) {
  return ref
      .watch(webSocketServiceProvider)
      .stream
      .where((event) => event.type == 'threat_score_update')
      .map((event) => ThreatScoreUpdate.fromJson(event.payload));
}

// MQTT sensor stream
@riverpod
Stream<SensorEvent> sensorStream(SensorStreamRef ref) {
  return ref.watch(mqttServiceProvider).subscribe(
    topic: 'safeher/glove/+/sensors',
    qos: MqttQos.atLeastOnce,
  );
}

// Offline-aware alert creation
@riverpod
class EmergencyNotifier extends AsyncNotifier<EmergencyState> {
  @override
  FutureOr<EmergencyState> build() => const EmergencyState.idle();

  Future<void> triggerAlert(AlertPayload payload) async {
    final connectivity = await ref.read(connectivityProvider.future);
    if (!connectivity.isConnected) {
      // Queue offline
      await ref.read(offlineQueueProvider.notifier).enqueue(payload);
      state = const AsyncData(EmergencyState.queued());
      return;
    }
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => ref.read(alertRepositoryProvider).createAlert(payload),
    );
    state = result.when(
      data: (alert) => AsyncData(EmergencyState.dispatched(alert)),
      error: (e, _) => AsyncData(EmergencyState.failed(e.toString())),
      loading: () => const AsyncLoading(),
    );
  }
}
```

### Offline Queue

```dart
// lib/core/services/offline_queue_service.dart
@singleton
class OfflineQueueService {
  late final Box<PendingAlertDto> _box;

  Future<void> init() async {
    Hive.registerAdapter(PendingAlertDtoAdapter());
    _box = await Hive.openBox<PendingAlertDto>('offline_alerts');
  }

  Future<void> enqueue(AlertPayload payload) async {
    await _box.add(PendingAlertDto.fromPayload(payload));
  }

  Future<void> drain(AlertRepository repo) async {
    if (_box.isEmpty) return;
    final pending = _box.values.toList();
    for (final item in pending) {
      try {
        await repo.createAlert(item.toPayload());
        await item.delete();
      } catch (e) {
        // Leave in queue; retry on next connectivity event
      }
    }
  }
}

// Drain on connectivity restore:
// In main.dart or app lifecycle listener:
ref.listen(connectivityProvider, (prev, next) {
  if (next.valueOrNull?.isConnected == true) {
    ref.read(offlineQueueServiceProvider).drain(
      ref.read(alertRepositoryProvider),
    );
  }
});
```

**Verification 5:**

```bash
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test --coverage
# Coverage must be > 70%
git add -A && git commit -m "feat: data layer complete"
git tag v0.5.0
```

---

## PHASE 6 — Final Audit & Polish

### Performance Audit Checklist

```bash
# Run Flutter DevTools Profile mode on Pixel 6a class device
flutter run --profile

# Check in DevTools Timeline:
# [ ] 0 jank frames on Home screen scroll
# [ ] 0 jank frames on Dashboard card appearance
# [ ] Threat gauge CustomPainter: single repaint layer
# [ ] Waveform CustomPainter: single repaint layer
# [ ] BackdropFilter: max 3 simultaneously

# Check with:
flutter build apk --release --analyze-size
# APK size must be < 80MB

# Cold start:
adb shell am start -W io.safeher.safeher_app/.MainActivity
# TotalTime must be < 2000ms
```

### Accessibility Audit Checklist

```bash
# Enable TalkBack (Android) / VoiceOver (iOS)
# Navigate every screen using screen reader only:
# [ ] Splash screen: no interaction needed; auto-advances
# [ ] Onboarding: pages swipeable; buttons labelled; skip accessible
# [ ] Login: all fields labelled; "Sign In" button; social logins labelled
# [ ] Signup: all fields labelled; strength bar has text description
# [ ] OTP: each box labelled "OTP digit 1" through "OTP digit 6"
# [ ] Home: SOS button has semantic label "Emergency SOS button"
# [ ] Emergency: all stages navigable; countdown announced
# [ ] Reports: timeline events readable in order

# Check contrast ratios with Flutter accessibility audit:
flutter test --tags accessibility
```

### Reduced Motion Audit

```bash
# Enable "Disable animations" in Android Developer Options
# Navigate all screens:
# [ ] No broken layouts
# [ ] All content visible
# [ ] Interactions work (no animation-dependent state)
# [ ] Emergency countdown still works (timer text, not animation-driven)
```

---

## PHASE 7 — Testing

### Widget Test Template

```dart
// test/features/home/home_screen_test.dart
void main() {
  group('HomeScreen', () {
    testWidgets('renders without exception — loading state', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Override with mock providers
            threatScoreStreamProvider.overrideWith(
              (_) => Stream.value(ThreatScoreUpdate.safe()),
            ),
            recentAlertsProvider.overrideWith(
              (_) async => <Alert>[],
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders with data', (tester) async { ... });
    testWidgets('SOS FAB navigates to emergency', (tester) async { ... });
    testWidgets('threat gauge shows correct colour for DANGER', (tester) async { ... });

    goldenTest('golden_home_dark', (tester) async {
      // dark mode golden
    });
    goldenTest('golden_home_light', (tester) async {
      // light mode golden
    });
  });
}
```

### Run All Tests

```bash
# First time (generate goldens):
flutter test --update-goldens

# Every subsequent run:
flutter analyze                    # 0 issues
flutter test --coverage           # > 70% coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html      # review coverage report

# E2E tests (requires connected device or emulator):
patrol test                        # Patrol E2E tests

# All must pass before tagging release
git add -A && git commit -m "test: all tests passing"
git tag v1.0.0
```

---

## ═══════════════════════════════════════════════════════════
## ACCEPTANCE CRITERIA — DONE WHEN ALL PASS
## ═══════════════════════════════════════════════════════════

```
FUNCTIONAL:
[ ] All 14+ screens render without exception on Android + iOS
[ ] All screens correct in dark mode AND light mode
[ ] SOS flow: tap → hold → countdown → alert → contacts notified (mock)
[ ] Offline SOS: disable WiFi → trigger → re-enable → alert sent
[ ] BLE pairing flow completes (with mock device or real hardware)
[ ] Device status updates live via MQTT stream
[ ] Threat score gauge animates smoothly to new values
[ ] Evidence recording starts within 1s of SOS trigger
[ ] Reports timeline renders chronologically with expandable events
[ ] Drag-to-reorder emergency contacts works with haptic

PERFORMANCE:
[ ] 60fps minimum on Home scroll (DevTools Profile verified)
[ ] 60fps on threat gauge animation
[ ] 60fps on audio waveform (30fps update rate; 60fps visual render)
[ ] Cold start < 2000ms on Pixel 6a class device
[ ] Release APK < 80MB

QUALITY:
[ ] flutter analyze: 0 issues
[ ] flutter test --coverage: > 70% line coverage
[ ] 0 golden test mismatches
[ ] 0 red screens (exception screens) on any route

ACCESSIBILITY:
[ ] TalkBack: all interactive elements reachable + labelled
[ ] Font scale 200%: no overflow, no clipped text
[ ] Reduced motion: all screens usable without animations
[ ] Contrast: all text meets WCAG 2.1 AA (4.5:1 minimum)

SECURITY:
[ ] No credentials in source code or committed .env files
[ ] JWT stored in flutter_secure_storage (not Hive)
[ ] Certificate pinning configured for production
[ ] No sensitive data logged to console in release mode
```

---

## ═══════════════════════════════════════════════════════════
## FINAL COMMIT SEQUENCE
## ═══════════════════════════════════════════════════════════

```bash
# After all phases complete and acceptance criteria pass:

flutter build apk --release
flutter build ios --release --no-codesign

git add -A
git commit -m "feat: SafeHer frontend v1.0.0 — all screens complete"
git tag v1.0.0 -m "SafeHer frontend — production ready"

echo "
════════════════════════════════════════════════
SafeHer Frontend — BUILD COMPLETE
════════════════════════════════════════════════
Screens:        16 screens fully implemented
Components:     22+ reusable components
Test coverage:  > 70%
Performance:    60fps verified
Accessibility:  WCAG 2.1 AA
APK size:       < 80MB
Cold start:     < 2000ms

Result: Instagram × Spotify × Apple
        — but uniquely SafeHer.
════════════════════════════════════════════════
"
```

---

*SafeHer — CLAUDE.md v2.1 | SRS + Frontend Codex | Production Build Guide*
*Place this file in project root as `CLAUDE.md` and run `claude` to begin.*
