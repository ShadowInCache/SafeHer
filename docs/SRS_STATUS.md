# SRS Compliance Status

**Last refreshed:** 2026-08-15
**Governing spec:** [`SRS.md`](../SRS.md) (2,851 lines)

This file answers one question: *how much of `SRS.md` is actually built, and
how do we know?* It is refreshed at the start of every working session, and
the [Session log](#session-log) at the bottom is append-only — earlier entries
are never rewritten, so the trajectory stays readable.

## How a claim gets a status here

| Status | Meaning |
|--------|---------|
| ✅ **Verified** | Implemented, and proven by a test or command whose output is recorded below. |
| 🟡 **Built, unverified** | The code exists and analyses clean, but nothing proves it works end to end. |
| ⛔ **Gap** | Not implemented. |
| ↔️ **Deviation** | Deliberately differs from the SRS. Rationale in [Deliberate deviations](#deliberate-deviations). |
| 🚧 **Blocked** | Needs hardware, a Mac, a production endpoint, or a human decision. |

A status is never upgraded on the strength of reading the code. Something has
to run.

---

## Blocking conditions (SRS "Stop and Fix Before Continuing")

All four gates pass as of the last refresh.

| Gate | Requirement | Last measured | Status |
|------|-------------|---------------|--------|
| `flutter analyze` | 0 issues | 0 issues | ✅ |
| `flutter test --coverage` | > 70% line coverage | **75.2%** (6,008 / 7,988 lines) | ✅ |
| `flutter build apk --release` | 0 errors | 68.5 MB APK, exit 0 | ✅ |
| `dart run build_runner build` | 0 conflicts | 46 outputs, 0 conflicts | ✅ |

Beyond the SRS's four, the repo also runs:

| Check | Last measured | Status |
|-------|---------------|--------|
| `flutter test` (full suite) | 520 passing, 0 failing | ✅ |
| `pytest tests/` (in-process suites) | 80 passing, 0 failing | ✅ |
| Alembic from empty → head → downgrade → head | 14 migrations, reversible | ✅ |

Coverage by area — the thin spots are where next session's tests should go:

| Area | Coverage |
|------|----------|
| `shared/components` | 96.4% |
| `features/emergency` | 87.0% |
| `features/home` | 81.6% |
| `features/auth` | 79.1% |
| `features/devices` | 76.7% |
| `features/reports` | 75.6% |
| `features/dashboard` | 66.4% |
| `features/monitoring` | 64.6% |
| `features/safety` | 47.9% |
| `core/network` | 32.1% |
| `features/contacts` | 12.1% |

---

## Acceptance criteria (SRS "DONE WHEN ALL PASS")

### Functional

| Criterion | Status | Evidence |
|-----------|--------|----------|
| All 14+ screens render without exception | ✅ Android/web | 25 screens across 14 SRS specs + extras; widget tests assert no exceptions. iOS unverified — 🚧 needs a Mac. |
| All screens correct in dark **and** light mode | 🟡 | 19 of 20 screen tests carry a light-mode case, with goldens in both themes. `safe_journey_screen_test.dart` is the exception. |
| SOS: tap → hold → countdown → alert → contacts notified | 🟡 | Covered by widget tests; never run against a live backend + real contacts. |
| Offline SOS: disable network → trigger → reconnect → sent | 🟡 | `core/offline` queue implemented and unit-tested; the physical airplane-mode run has not been done. |
| BLE pairing flow completes | 🚧 | Works against the fake BLE service. Real hardware not yet paired. |
| Device status updates live via MQTT | 🟡 | WebSocket path implemented (`realtime_client.dart`); MQTT worker exists backend-side, untested against a broker. |
| Threat gauge animates smoothly to new values | ✅ | `SaThreatGauge` component tests + goldens. |
| Evidence recording starts within 1s of SOS | 🚧 | Needs a device; not measurable in the widget test binding. |
| Reports timeline renders chronologically, expandable | ✅ | `reports` tests. |
| Drag-to-reorder contacts with haptic | ✅ | `emergency_contacts_screen_test.dart`. |

### Performance

| Criterion | Status | Note |
|-----------|--------|------|
| 60fps on Home scroll | 🚧 | Requires DevTools Profile on a physical device. |
| 60fps threat gauge / waveform | 🚧 | Same. |
| Cold start < 2000ms | 🚧 | Same. |
| Release APK < 80MB | ✅ | 68.5 MB. |

### Quality

| Criterion | Status |
|-----------|--------|
| `flutter analyze`: 0 issues | ✅ |
| Coverage > 70% | ✅ 75.2% |
| 0 golden mismatches | ✅ |
| 0 red screens on any route | ✅ every route has a test that asserts no exception |

### Accessibility

| Criterion | Status | Note |
|-----------|--------|------|
| TalkBack: all interactive elements labelled | 🟡 | `Semantics()` is applied throughout (SRS Rule 9) but no screen-reader pass has been done. |
| Font scale 200%: no overflow | ⛔ | **Untested.** No test currently pumps at `textScaleFactor: 2.0`. |
| Reduced motion: all screens usable | ✅ | Every animation routes through `AnimationHelpers`, which checks `MediaQuery.disableAnimations`. |
| Contrast ≥ 4.5:1 | 🟡 | Palette designed to the SRS spec; not machine-verified. |

### Security

| Criterion | Status | Note |
|-----------|--------|------|
| No credentials in source or committed `.env` | ✅ | CI fails the build if `.env`, `*.db`, `__pycache__` or a browser profile is ever tracked. |
| JWT in `flutter_secure_storage`, not Hive | ✅ | `core/network/auth_token_store.dart`. |
| Certificate pinning for production | ⛔ | **Gap.** Nothing in `lib/` pins a certificate. |
| No sensitive data logged in release | 🟡 | No `print()` in the network layer; not audited app-wide. |

---

## Screens (SRS Part 3, Phase 4)

All 14 SRS screens exist and are routed.

| # | Screen | Route | Status |
|---|--------|-------|--------|
| 1 | Splash | `/` | ✅ |
| 2 | Onboarding | `/onboarding` | ✅ |
| 3 | Login | `/auth/login` | ✅ |
| 4 | Signup | `/auth/signup` | ✅ |
| 5 | OTP Verification | `/auth/otp` | ✅ |
| 6 | Home | `/home` | ✅ |
| 7 | Device Management | `/devices`, `/devices/:id` | ✅ |
| 8 | Live Monitoring | `/monitor` | ✅ |
| 9 | **Dashboard** | `/dashboard` | ✅ **new 2026-08-15** |
| 10 | Search | `/search` | ✅ |
| 11 | Emergency | `/emergency` | ✅ |
| 12 | Reports | `/reports`, `/reports/:id` | ✅ |
| 13 | Profile | `/profile` | ✅ |
| 14 | Settings | `/settings` + sub-routes | ✅ |

Beyond the SRS: Forgot Password (`/auth/forgot`) and the Safety Toolkit
(`/safety` and six sub-routes — nearby places, safe journey, helplines, fake
call, guides, safety PIN).

**Bottom navigation now matches the SRS** — Home / Monitor / Dashboard /
Profile plus the centre SOS FAB. Device Management moved off the nav bar,
where the spec never put it; it stays one tap from Home, Profile and Search.

---

## Component library (SRS Phase 2)

All 17 specified component groups exist under `lib/shared/components/`, at
**96.4% line coverage** with goldens in both themes. `SaHeatGrid` was added
2026-08-15 for the Dashboard's location map.

---

## Functional requirements

### §4.1 Authentication

| ID | Requirement | Status |
|----|-------------|--------|
| FR-AUTH-01 | Email + password with OTP verification | ✅ `auth_security.py`, 27 tests |
| FR-AUTH-02 | Google Sign-In via Firebase | ✅ wired; SHA-1 registered for Android |
| FR-AUTH-03 | Apple Sign-In (iOS) | 🚧 implemented via `AppleAuthProvider` in `auth_repository_remote.dart`; unverifiable without a Mac |
| FR-AUTH-04 | JWT 15 min + refresh 30 days | ✅ |
| FR-AUTH-05 | Biometric unlock | 🟡 `core/biometrics/` exists; end-to-end unlock never exercised |
| FR-AUTH-06 | Session invalidation on password change | ✅ `tokens_valid_from` |
| FR-AUTH-07 | 5 failures → 15-min lockout | ✅ incl. `Retry-After` header |
| FR-AUTH-08 | Deletion with 30-day grace | ✅ hourly purge worker |

### §4.2 Device Management

| ID | Requirement | Status |
|----|-------------|--------|
| FR-DEV-01/02 | BLE pairing, glove + glasses | 🚧 fake BLE service only |
| FR-DEV-03 | Real-time battery, low at 20% | 🟡 |
| FR-DEV-04 | Firmware OTA, SHA-256 verified | ⛔ **Gap** — UI shows `updateAvailable`; no OTA pipeline |
| FR-DEV-05 | Disconnection alert within 5s | 🟡 |
| FR-DEV-06 | Up to 3 named device sets | ⛔ **Gap** |
| FR-DEV-07 | Device health diagnostics | ✅ surfaced on the new Dashboard + device screen |

### §4.3 Emergency System

| ID | Requirement | Status |
|----|-------------|--------|
| FR-EMG-01 | Manual SOS, dispatched < 3s | 🟡 |
| FR-EMG-02 | Auto-SOS at threat ≥ 0.75 | 🟡 backend threshold implemented |
| FR-EMG-03 | 10s countdown, cancellable | ✅ |
| FR-EMG-04 | FCM + SMS to all contacts | 🟡 FCM implemented; SMS provider not configured |
| FR-EMG-05 | Alert payload contents | ✅ |
| FR-EMG-06 | Auto-start evidence recording | 🚧 needs a device |
| FR-EMG-07 | AES-256 at rest + TLS 1.3 | ⛔ **Gap** — no evidence-encryption test suite |
| FR-EMG-08 | False-alarm cancellation logged | ✅ |
| FR-EMG-09 | Offline emergency queue | ✅ `core/offline` |
| FR-EMG-10 | Up to 10 contacts, drag priority, OTP per contact | 🟡 drag + limit done; per-contact OTP confirmation missing |

### §4.4 Live Monitoring

| ID | Requirement | Status |
|----|-------------|--------|
| FR-MON-01 | Sensor feed < 500ms | ↔️ see deviations — the backend broadcasts discrete events, not a stream |
| FR-MON-02 | Live video preview | 🚧 |
| FR-MON-03 | Audio waveform at 30 FPS | 🟡 `SaWaveform` built; no live mic source |
| FR-MON-04 | Threat gauge real-time | ✅ |
| FR-MON-05 | GPS on map, 5m, offline tiles | 🟡 no offline tile cache |
| FR-MON-06 | 60s motion timeline with event pins | 🟡 `SaMotionChart` built; no live feed |

### §4.5 Reports & Analytics

| ID | Requirement | Status |
|----|-------------|--------|
| FR-RPT-01 | AI incident summary | 🟡 |
| FR-RPT-02 | Timeline ±100ms | ✅ |
| FR-RPT-03 | PDF export, chain-of-custody hash | ⛔ **Gap** — no PDF code anywhere |
| FR-RPT-04 | Safety analytics heatmap | ✅ **new** — `SaHeatGrid` + `/dashboard/analytics` |
| FR-RPT-05 | Threat history chart, tap for detail | ✅ **new** — 14-day chart, tap opens that day's breakdown |
| FR-RPT-06 | Share report via 7-day expiring link | ⛔ **Gap** |

---

## Deliberate deviations

These differ from the SRS on purpose. Each is a decision, not an omission.

**Monolith, not ten microservices (§7.1).** The SRS lists ten services on
ports 8000–8009. The repo runs one FastAPI app with ten routers. Same
endpoints, same boundaries, one deployable — splitting it would add ten
failure modes to a product whose defining requirement is that an alert gets
out. The port table is the target topology if scale ever demands it.

**Postgres/SQLAlchemy, not Firestore (§8).** The schema in §8 is Firestore
documents with security rules; the repo uses SQLAlchemy models against
Supabase Postgres, with Alembic migrations. The data *shape* follows §8;
the store does not. Firestore's per-document security rules are replaced by
row-level ownership checks in each router.

**Live Monitoring shows events, not a stream (FR-MON-01).** There is no
continuous sensor feed to render — the backend broadcasts discrete
`threat_alert` / `emergency_alert` events. The screen shows real connection
state and a real event list rather than a fabricated waveform.

**Heat grid, not Google Maps (SCREEN 9, Card 3).** The SRS allows either.
The grid was chosen because it needs no Maps API key and — the reason that
decided it — cannot render a recognisable street corner where a woman was
attacked. Cells are aggregated server-side to ~1.1 km.

**No battery trend line (SCREEN 9, Card 6).** The schema stores one current
battery reading per device, not a series. The API returns
`device_battery_history_available: false` and the card says "Current
battery". Drawing a trend from a single sample would be a fabricated chart.

---

## Ranked open gaps

Ordered by what a user would miss first.

1. **Certificate pinning** (§5.2, acceptance criteria) — a safety app
   sending GPS and evidence over TLS with no pin is one hostile network away
   from a readable session.
2. **PDF export + share link** (FR-RPT-03, FR-RPT-06) — an incident report
   that cannot leave the phone is of limited use to police or a lawyer.
3. **Per-contact OTP confirmation** (FR-EMG-10) — an unconfirmed contact is
   an alert sent into the void.
4. **Font-scale 200% testing** (§5.4) — cheap to add, and the most likely
   source of a broken layout in the field.
5. **Evidence encryption test suite** (FR-EMG-07).
6. **Firmware OTA + device sets** (FR-DEV-04, FR-DEV-06).
7. **Coverage in the thin areas** — `features/contacts` at 12.1% and
   `core/network` at 32.1% are the weakest points in an otherwise healthy
   75.2%.
8. **iOS verification** 🚧 — the `project.pbxproj` edit registering
   `GoogleService-Info.plist` is the one change in the repo nobody has
   compiled. Needs `flutter build ios --debug` on a Mac.

---

## Session log

Append-only. Newest last.

### 2026-08-15 — SCREEN 9 Dashboard

The last missing SRS screen. A prior decision had folded analytics into Home
and dropped the Dashboard tab; the SRS specifies both, answering different
questions ("am I safe now" vs "what has been happening to me"), so the screen
was built and the nav bar restored to the specified four tabs.

- **Backend:** new `GET /api/v1/dashboard/analytics` — 30-day trend with a
  null-when-no-baseline delta, 14-day per-severity breakdown, incident
  location heatmap aggregated to ~1.1 km cells, device health, and a
  severity-weighted weekly safety score. 13 new tests, all pinning honesty
  properties (null trend, empty heatmap, explicit "no battery history").
- **Frontend:** `DashboardScreen` with all seven SRS cards, staggered entry,
  shimmer skeleton, pull-to-refresh, empty and error states. New `SaHeatGrid`
  CustomPainter component. 13 new tests + goldens in both themes.
- **Two real bugs found and fixed while testing:** `IntrinsicHeight` around
  cards containing a `LayoutBuilder` threw during layout (would have crashed
  in production, not just in tests); and the stagger's `Future.delayed`
  leaked a timer whenever a card scrolled out of the lazily-built sliver —
  replaced with an `Interval` baked into the controller duration.
- **First coverage measurement ever taken: 75.2%**, above the SRS's 70% gate.

Totals after this session: 520 Flutter tests, 80 backend tests, all green.
