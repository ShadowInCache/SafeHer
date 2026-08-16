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

---

## §4.1 Authentication

| ID | Status | Implementation |
|----|--------|----------------|
| FR-AUTH-01 | done | `fastapi_app/repositories/auth_security.py`, `fastapi_app/services/email.py` |
| FR-AUTH-02 | done | `mobile/lib/features/auth/data/auth_repository_remote.dart` |
| FR-AUTH-03 | partial | `mobile/lib/features/auth/data/auth_repository_remote.dart` — never compiled on iOS |
| FR-AUTH-04 | done | `fastapi_app/security.py`, `mobile/lib/core/network/api_client.dart` |
| FR-AUTH-05 | partial | `mobile/lib/core/biometrics/biometric_service.dart` — never exercised on a device |
| FR-AUTH-06 | done | `fastapi_app/repositories/auth_security.py` |
| FR-AUTH-07 | done | `fastapi_app/repositories/auth_security.py` |
| FR-AUTH-08 | done | `fastapi_app/workers/deletion_purge.py` |

## §4.2 Device Management

| ID | Status | Implementation |
|----|--------|----------------|
| FR-DEV-01 | partial | `mobile/lib/features/devices/data/ble_providers.dart` — only against a fake service |
| FR-DEV-02 | partial | `mobile/lib/features/devices/data/ble_providers.dart` — only against a fake service |
| FR-DEV-03 | done | `mobile/lib/features/devices/data/device_repository_remote.dart`, `fastapi_app/routers/devices.py` |
| FR-DEV-04 | not built | Firmware OTA has no implementation anywhere |
| FR-DEV-05 | partial | `mobile/lib/features/devices/data/ble_providers.dart` — reconnect handling exists; the 5s push is not wired |
| FR-DEV-06 | not built | Named device sets have no implementation |
| FR-DEV-07 | done | `mobile/lib/features/dashboard/presentation/dashboard_screen.dart` |

## §4.3 Emergency System

| ID | Status | Implementation |
|----|--------|----------------|
| FR-EMG-01 | done | `mobile/lib/features/emergency/presentation/emergency_screen.dart` |
| FR-EMG-02 | done | `fastapi_app/routers/alerts.py` |
| FR-EMG-03 | done | `mobile/lib/features/emergency/presentation/emergency_screen.dart` |
| FR-EMG-04 | partial | `fastapi_app/services/emergency_dispatch.py` — email verified live; SMS unconfigured (paid) |
| FR-EMG-05 | partial | `fastapi_app/services/emergency_dispatch.py` — evidence URL follows in a second email, not the alert |
| FR-EMG-06 | done | `mobile/lib/core/evidence/evidence_recorder_io.dart` — audio; video deliberately not attempted |
| FR-EMG-07 | done | `fastapi_app/services/evidence_store.py` |
| FR-EMG-08 | done | `mobile/lib/features/emergency/presentation/emergency_screen.dart` |
| FR-EMG-09 | done | `mobile/lib/core/offline/offline_queue_service.dart` |
| FR-EMG-10 | done | `fastapi_app/services/contact_verification.py`, `fastapi_app/routers/users.py` |

## §4.4 Live Monitoring

| ID | Status | Implementation |
|----|--------|----------------|
| FR-MON-01 | partial | `mobile/lib/features/monitoring/presentation/live_monitoring_screen.dart` — discrete events, no continuous feed |
| FR-MON-02 | not built | Live video preview from the glasses has no implementation |
| FR-MON-03 | partial | `mobile/lib/shared/components/charts/sa_waveform.dart` — component built, no live mic source |
| FR-MON-04 | done | `mobile/lib/shared/components/charts/sa_threat_gauge.dart` |
| FR-MON-05 | partial | `mobile/lib/features/reports/presentation/widgets/report_breadcrumb_map.dart` — no offline tile cache |
| FR-MON-06 | partial | `mobile/lib/shared/components/charts/sa_motion_chart.dart` — component built, no live feed |

## §4.5 Reports & Analytics

| ID | Status | Implementation |
|----|--------|----------------|
| FR-RPT-01 | partial | `fastapi_app/services/incident_summary.py` — generated in ~40s, over the SRS's 30s target |
| FR-RPT-02 | done | `mobile/lib/features/reports/domain/models/timeline_event.dart` |
| FR-RPT-03 | done | `fastapi_app/services/incident_pdf.py` |
| FR-RPT-04 | done | `mobile/lib/shared/components/charts/sa_heat_grid.dart`, `fastapi_app/routers/dashboard.py` |
| FR-RPT-05 | done | `mobile/lib/features/dashboard/presentation/dashboard_screen.dart` |
| FR-RPT-06 | done | `fastapi_app/routers/shares.py` |

---

## What is genuinely not built

Three requirements, all of which need hardware this project does not have:

- **FR-DEV-04** firmware OTA — needs real device firmware to update.
- **FR-DEV-06** named device sets — needs more than one device set to exist.
- **FR-MON-02** live video from the glasses — needs the glasses.

Everything else is at least partial, with the limitation stated rather than
implied.
