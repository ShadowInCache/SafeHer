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
| FR-EMG-06 | done | `mobile/lib/core/evidence/evidence_recorder_io.dart` — audio; video deliberately not attempted |
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
| §10.1 Flutter coverage > 70% | unmeasured | 587 tests pass; line coverage not measured |
| §10.2 TC-EMG-01 auto-alert | done | `tests/test_threat_fusion.py` |
| §10.2 TC-EMG-05 deduplication | done | `tests/test_threat_fusion.py` |

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

## What is genuinely not built

Three requirements, all of which need hardware this project does not have:

- **FR-DEV-04** firmware OTA — needs real device firmware to update.
- **FR-DEV-06** named device sets — needs more than one device set to exist.
- **FR-MON-02** live video from the glasses — needs the glasses.

Everything else is at least partial, with the limitation stated rather than
implied.
