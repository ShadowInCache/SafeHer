# SRS Traceability

Every functional requirement in [`SRS.md`](../SRS.md), mapped to the code
that implements it.

This exists because "verify it against the SRS" was, until now, something
only a person reading both documents could do. A first attempt at an
automated audit reported 20 of 37 requirements as unimplemented — almost all
of which were built, just never linked to the requirement they satisfy. The
gap was traceability, not code, and that distinction is exactly what this
file records.

`test_traceability.py` enforces it: every requirement in `SRS.md` must
appear below, and every path named must exist. A requirement can be marked
**not built** — that is an honest state — but it cannot be left out.

Status values: **done** (implemented and tested), **partial** (works, with a
stated limitation), **not built**.

> **Last full audit: 2026-08-17.** Every row below was re-read against the
> code rather than carried forward. That audit found one requirement marked
> `done` that was not implemented at all (FR-EMG-02) — see *What the audit
> corrected*, at the bottom. Statuses here are deliberately pessimistic:
> where the SRS names a mechanism that does not exist, the row says so even
> if the feature broadly works.

---

## §4.1 Authentication

| ID | Status | Implementation |
|----|--------|----------------|
| FR-AUTH-01 | done | `fastapi_app/repositories/auth_security.py`, `fastapi_app/services/email.py` |
| FR-AUTH-02 | done | `mobile/lib/features/auth/data/auth_repository_remote.dart`, `fastapi_app/routers/auth.py` |
| FR-AUTH-03 | partial | `mobile/lib/features/auth/data/auth_repository_native.dart` — written, never compiled on iOS |
| FR-AUTH-04 | done | `fastapi_app/security.py`, `mobile/lib/core/network/api_client.dart` — 15 min / 30 days, per spec |
| FR-AUTH-05 | partial | `mobile/lib/core/biometrics/biometric_service.dart` — never exercised on a device |
| FR-AUTH-06 | done | `fastapi_app/repositories/auth_security.py` |
| FR-AUTH-07 | done | `fastapi_app/repositories/auth_security.py` — 5 failures / 15 min, per spec |
| FR-AUTH-08 | done | `fastapi_app/workers/deletion_purge.py` |

## §4.2 Device Management

| ID | Status | Implementation |
|----|--------|----------------|
| FR-DEV-01 | partial | `mobile/lib/features/devices/data/ble_service_flutter_blue_plus.dart` — scan/connect/discover verified on real hardware 2026-08-17; **no 6-digit PIN step**, which needs firmware to present one |
| FR-DEV-02 | partial | `mobile/lib/features/devices/data/ble_service_flutter_blue_plus.dart` — same as FR-DEV-01; the glasses themselves do not exist |
| FR-DEV-03 | done | `mobile/lib/features/devices/data/device_repository_remote.dart`, `fastapi_app/routers/devices.py` — 60s online window, 20% low-battery band |
| FR-DEV-04 | not built | Firmware OTA has no implementation anywhere |
| FR-DEV-05 | partial | `mobile/lib/features/devices/data/ble_providers.dart` — reconnect handling exists; the 5s push is not wired |
| FR-DEV-06 | not built | Named device sets have no implementation |
| FR-DEV-07 | done | `mobile/lib/features/dashboard/presentation/dashboard_screen.dart` |

## §4.3 Emergency System

| ID | Status | Implementation |
|----|--------|----------------|
| FR-EMG-01 | done | `mobile/lib/features/emergency/presentation/emergency_screen.dart` |
| FR-EMG-02 | done | `fastapi_app/services/threat_fusion.py`, `fastapi_app/routers/alerts.py` — built 2026-08-17; previously marked done while not existing |
| FR-EMG-03 | done | `mobile/lib/features/emergency/presentation/emergency_screen.dart` |
| FR-EMG-04 | partial | `fastapi_app/services/emergency_dispatch.py` — email and push both verified against live services; 3 attempts per contact per spec; **SMS unconfigured** (Twilio is paid) |
| FR-EMG-05 | partial | `fastapi_app/services/emergency_dispatch.py` — evidence URL follows in a second email, not the alert |
| FR-EMG-06 | partial | `mobile/lib/core/evidence/evidence_recorder_io.dart` (audio), `video_recorder_io.dart` (video) — both capture on device; the camera is the phone's, not the glasses', so video only helps when the lens happens to be pointed at something |
| FR-EMG-07 | done | `fastapi_app/services/evidence_store.py` — AES-256-GCM |
| FR-EMG-08 | done | `mobile/lib/features/emergency/presentation/emergency_screen.dart` |
| FR-EMG-09 | done | `mobile/lib/core/offline/offline_queue_service.dart` |
| FR-EMG-10 | done | `fastapi_app/services/contact_verification.py`, `fastapi_app/routers/users.py` — max 10 per spec |

## §4.4 Live Monitoring

| ID | Status | Implementation |
|----|--------|----------------|
| FR-MON-01 | partial | `mobile/lib/features/monitoring/presentation/live_monitoring_screen.dart` — discrete events, no continuous feed (nothing produces one) |
| FR-MON-02 | not built | Live video preview from the glasses has no implementation |
| FR-MON-03 | partial | `mobile/lib/shared/components/charts/sa_waveform.dart` — component built, no live mic source |
| FR-MON-04 | done | `mobile/lib/shared/components/charts/sa_threat_gauge.dart` |
| FR-MON-05 | partial | `mobile/lib/features/reports/presentation/widgets/report_breadcrumb_map.dart` — needs a Maps API key; no offline tile cache |
| FR-MON-06 | partial | `mobile/lib/shared/components/charts/sa_motion_chart.dart` — component built, no live feed |

## §4.5 Reports & Analytics

| ID | Status | Implementation |
|----|--------|----------------|
| FR-RPT-01 | partial | `fastapi_app/services/incident_summary.py` — generated in ~40s, over the SRS's 30s target |
| FR-RPT-02 | done | `mobile/lib/features/reports/domain/models/timeline_event.dart` |
| FR-RPT-03 | done | `fastapi_app/services/incident_pdf.py` — chain-of-custody hashes |
| FR-RPT-04 | done | `mobile/lib/shared/components/charts/sa_heat_grid.dart`, `fastapi_app/routers/dashboard.py` |
| FR-RPT-05 | done | `mobile/lib/features/dashboard/presentation/dashboard_screen.dart` |
| FR-RPT-06 | done | `fastapi_app/routers/shares.py` — expiring, read-only |

---

## Algorithms and targets outside the FR tables

The SRS specifies more than the numbered requirements. These are tracked
because nothing else would catch them drifting.

| Spec | Status | Notes |
|------|--------|-------|
| §6.2 fusion weights, EMA, boosters, dedup | partial | `fastapi_app/services/threat_fusion.py` implements all of it; `fuse()` is unreachable end to end until firmware produces motion/audio/vision scores |
| §10.1 backend coverage > 80% | **not met** | Measured 62% on 2026-08-17 (`pytest --cov=fastapi_app`), up from 58% before this audit's tests |
| §10.1 Flutter coverage > 70% | unmeasured | 596 tests pass; line coverage not measured |
| §5.2 no cleartext in release | done | `mobile/android/app/src/main/res/xml/network_security_config.xml` forbids it; debug and profile permit it for LAN testing. Verified against the packaged resources of both variants, not the source. |
| §10.2 TC-EMG-01 auto-alert | done | `tests/test_threat_fusion.py` |
| §10.2 TC-EMG-05 deduplication | done | `tests/test_threat_fusion.py` |
| §6.1 three-model pipeline | scaffolded | `fastapi_app/services/threat_models.py` — contract, registry and `POST /alerts/analyze` ready; **no model trained**, so nothing produces these scores yet |

---

## What the audit corrected

**FR-EMG-02 was marked `done` and did not exist.** The row pointed at
`fastapi_app/routers/alerts.py`, which accepted a threat score, mapped it to
a colour band and stored it. Nothing compared it to a threshold; nothing
dispatched. The AI path (`/process-threat`) pushed a notification to the
user's *own* phone and stopped there — her emergency contacts were never
told unless she pressed SOS herself, which is precisely the case FR-EMG-02
exists to cover.

Compounding it, the mobile app had shipped a "threat threshold" slider on
the Profile screen that wrote to Hive and was read by nothing. A user could
set it to 60% and reasonably believe SafeHer would raise the alarm for her.

Now built: `threat_fusion.py` implements §6.2 in full, the decision runs on
both paths that carry a score, the threshold is stored per user and the
slider syncs to it. Twenty-one tests pin it.

**A float comparison would have suppressed a boundary alert.** Smoothing a
constant 0.75 yields 0.7499999999999999, which is `<` a 0.75 threshold — so
a sustained threat sitting exactly at the user's setting would never have
fired. Found by the boundary test, fixed with an epsilon.

**Two SRS internal contradictions**, recorded rather than silently resolved:

- The dedup window is **120s** in §6.2 and **60s** in §8.2 and TC-EMG-05.
  The longer window is implemented: a suppressed duplicate is a nuisance,
  a second dispatch spams every contact of a woman already in an emergency.
- §6.2 writes the night window as `hour in range(22, 6)`, which is empty in
  Python and would boost nothing. Implemented as the 22:00–05:59 window it
  describes.

---

## The ML pipeline — ready, not running

The product design is three models feeding SRS §6.2's fusion:

| Modality | Algorithm | Device | Sensor |
|----------|-----------|--------|--------|
| motion | XGBoost | glove | MPU6050 accelerometer + gyroscope |
| audio | CNN + LSTM | glasses | microphone |
| vision | YOLOv8 | glasses | camera (also yields `weapon_confidence`) |

**No model is trained.** `POST /api/v1/alerts/analyze` accepts per-model
scores and runs the full §6.2 pipeline — fuse, smooth, boost, threshold,
deduplicate, dispatch — so training a model is a configuration change rather
than an integration project. `GET /api/v1/alerts/models` reports the state
honestly, including `scores_are_caller_supplied: true` while nothing is
trained: every score the backend currently sees came from a caller, not from
SafeHer's own inference.

The endpoint takes *scores*, not frames, deliberately. SRS §6.3 splits
inference across firmware and GPU-enabled Cloud Run, and an ESP32-WROOM-32E
cannot run YOLOv8 whatever the ambition — so a model can move between
firmware, phone and server without this contract changing.

Video capture landed on 2026-08-17: `video_recorder_io.dart` records
alongside audio during an SOS and uploads to the same encrypted evidence
store. It also gives YOLOv8 an input path, which did not exist before —
until then the weapon model had nowhere to read frames from even in
principle.

Video is captured *in addition to* audio and never instead of it. A phone in
a pocket films a pocket, which is why audio was built first and alone, and
that has not stopped being true. So a camera that cannot open costs nothing:
its failure is swallowed, audio uploads first, and an oversized video (the
server caps evidence at 25 MB, about a minute at this preset) degrades to a
missing video rather than a lost recording.

**Two deviations from the SRS, recorded rather than assumed:**

- **Heart rate is not in the spec.** §6.2 has no weight for it and the §9.1
  glove BOM has no pulse sensor; the "heartbeat" in §7.3 is a 30-second MQTT
  keepalive. It is carried as a small additive booster above 120 bpm, not a
  fourth fusion weight, so §6.2's arithmetic stays exactly as specified. An
  elevated pulse is evidence of running for a bus, so it can nudge a score
  other sensors already find alarming and cannot raise the alarm alone.
- **A missing modality is excluded, not zeroed.** The glasses can be off
  while the glove transmits. Zero-filling caps the achievable score at 0.75
  with no camera, and at 0.40 with the glove alone — which would silently
  disable auto-SOS. Weights are renormalised over whichever sensors
  reported.

## Notifying police or help centres — not built

`GET /api/v1/safety/nearby` finds real nearby police stations and hospitals.
Nothing **notifies** them, and `routers/journeys.py` states this explicitly.

This is deliberate and should stay deliberate until a real integration
exists. A safety app that implies it has called for help when it has not is
worse than one that never claimed to — a woman who believes police are
already coming may not call them herself. The same reasoning stopped a
Firebase campaign on 2026-08-16 that broadcast exactly that claim.

What it needs: an actual dispatch channel with someone accountable at the
other end. There is no public API for police dispatch in India; ERSS-112 has
no third-party integration. Realistic near-term options are a monitored
helpline mailbox or an SMS/voice channel to a partner NGO — each of which is
an agreement first and code second.

## What is genuinely not built

Three requirements, all of which need hardware this project does not have:

- **FR-DEV-04** firmware OTA — needs real device firmware to update.
- **FR-DEV-06** named device sets — needs more than one device set to exist.
- **FR-MON-02** live video from the glasses — needs the glasses.

Everything else is at least partial, with the limitation stated rather than
implied.
