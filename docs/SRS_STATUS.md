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
| `flutter test --coverage` | > 70% line coverage | **75.2%** (6,024 / 8,009 lines) | ✅ |
| `flutter build apk --release` | 0 errors | 68.5 MB APK, exit 0 | ✅ |
| `dart run build_runner build` | 0 conflicts | 46 outputs, 0 conflicts | ✅ |

Beyond the SRS's four, the repo also runs:

| Check | Last measured | Status |
|-------|---------------|--------|
| `flutter test` (full suite) | 584 passing, 0 failing | ✅ |
| `pytest tests/` (in-process suites) | 195 passing, 0 failing | ✅ |
| Alembic from empty → head → downgrade → head | 16 migrations, reversible | ✅ |

Coverage by area — the thin spots are where next session's tests should go:

| Area | Coverage |
|------|----------|
| `shared/components` | 96.4% |
| `features/emergency` | 87.0% |
| `features/home` | 81.6% |
| `features/auth` | 79.1% |
| `features/devices` | 76.7% |
| `features/reports` | 75.6% |
| `features/dashboard` | 65.9% |
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
| SOS: tap → hold → countdown → alert → contacts notified | ✅ **verified live** | Real SOS against the running backend delivered to a real inbox: `contacts_total 1, contacts_notified 1`, audit row `email sent`. SMS remains unconfigured (paid). |
| Offline SOS: disable network → trigger → reconnect → sent | 🟡 | `core/offline` queue implemented and unit-tested; the physical airplane-mode run has not been done. |
| BLE pairing flow completes | 🚧 | Works against the fake BLE service. Real hardware not yet paired. **Not available on web at all** — see the 2026-08-15 log entry. |
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
| Font scale 200%: no overflow | ✅ | `test/accessibility/font_scale_test.dart` pumps the component library at 200% (and 300%) in both themes, asserting no overflow exception. Found and fixed a real 1px overflow in the bottom nav. |
| Reduced motion: all screens usable | ✅ | Every animation routes through `AnimationHelpers`, which checks `MediaQuery.disableAnimations`. |
| Contrast ≥ 4.5:1 | 🟡 | Palette designed to the SRS spec; not machine-verified. |

### Security

| Criterion | Status | Note |
|-----------|--------|------|
| No credentials in source or committed `.env` | ✅ | CI fails the build if `.env`, `*.db`, `__pycache__` or a browser profile is ever tracked. |
| JWT in `flutter_secure_storage`, not Hive | ✅ | `core/network/auth_token_store.dart`. |
| Certificate pinning for production | ✅ HTTP **and** WebSocket | `core/network/certificate_pinning.dart` pins the leaf certificate on both the API and refresh clients, with pins supplied at build time via `--dart-define=PINNED_CERT_SHA256`. The live-monitoring socket is pinned too, via a no-trusted-roots `HttpClient` with validity and pin checks re-applied by hand. |
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
| FR-EMG-01 | Manual SOS, dispatched < 3s | 🟡 Chain complete; the < 3s budget has not been measured against a live Twilio round trip |
| FR-EMG-02 | Auto-SOS at threat ≥ 0.75 | 🟡 backend threshold implemented |
| FR-EMG-03 | 10s countdown, cancellable | ✅ |
| FR-EMG-04 | FCM + SMS to all contacts | ✅ email **verified end to end**; SMS ⛔ unconfigured (paid). `emergency_dispatch.py` — priority order, per-contact isolation, 3 attempts. Channels: email (SMTP, working), SMS (Twilio, paid), push (when a contact is a SafeHer user) |
| FR-EMG-05 | Alert payload contents | ✅ name, time, maps link, within the 160-char budget. Evidence URL is carried when one exists (see FR-EMG-06) |
| FR-EMG-06 | Auto-start evidence recording | ✅ audio, starting with the countdown (ahead of the 1s requirement). Video deliberately not attempted — see the log |
| FR-EMG-07 | AES-256 at rest + TLS 1.3 | ✅ AES-256-GCM at rest, owner-only retrieval, 22 tests. TLS in transit is the deployment's job (cert pinning is done client-side) |
| FR-EMG-08 | False-alarm cancellation logged | ✅ |
| FR-EMG-09 | Offline emergency queue | ✅ `core/offline` |
| FR-EMG-10 | Up to 10 contacts, drag priority, OTP per contact | ✅ all three. Ten-contact cap enforced server-side; per-contact code emailed to the contact and read back by the user |

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
| FR-RPT-03 | PDF export, chain-of-custody hash | ✅ SHA-256 per recording plus a document hash, stated as an integrity check rather than a signature |
| FR-RPT-04 | Safety analytics heatmap | ✅ **new** — `SaHeatGrid` + `/dashboard/analytics` |
| FR-RPT-05 | Threat history chart, tap for detail | ✅ **new** — 14-day chart, tap opens that day's breakdown |
| FR-RPT-06 | Share report via 7-day expiring link | ✅ token-only, revocable, evidence streamed per request so expiry actually withdraws access |

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

Ordered by what a user would miss first. Full requirement-by-requirement
mapping lives in [TRACEABILITY.md](TRACEABILITY.md), which is enforced by a
test rather than maintained by hand.

1. **SMS delivery** — the only channel that reaches a contact who does not
   check email, and the only one that reliably wakes someone at 2am. Costs
   money with every provider (OneSignal included, since its free-tier SMS
   wraps your own Twilio account). A deliberate deferral, not an oversight.
2. **Live monitoring is event-driven, not continuous** (FR-MON-01/03/06).
   The components exist — waveform, motion chart, gauge — but no continuous
   sensor feed reaches them, because the backend broadcasts discrete events
   and no wearable has ever connected.
3. **Coverage in the thin areas** — `features/contacts` and `core/network`
   are the weakest points in an otherwise healthy total.
4. **iOS verification** — the `project.pbxproj` edit registering
   `GoogleService-Info.plist` is the one change in the repo nobody has
   compiled. Needs `flutter build ios --debug` on a Mac.
5. **Real hardware** — BLE pairing has only ever run against a fake service;
   no glove or glasses has been paired. Performance targets (60fps, cold
   start) also need a physical device to measure.

**Genuinely not built** — four requirements, each needing something this
project does not have: firmware OTA (FR-DEV-04), named device sets
(FR-DEV-06), live video from the glasses (FR-MON-02), and AI-generated
incident summaries (FR-RPT-01, needs a paid model API).

---

## Session log

Append-only. Newest last.

### 2026-08-15 — SCREEN 9 Dashboard, certificate pinning, font-scale testing

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

Then two gaps the new status report had ranked at the top:

**Certificate pinning (SRS §5.2, ranked #1).** `applyCertificatePinning`
installs a leaf-certificate check on both the API client and the refresh
client — the refresh path carries the long-lived token, so leaving it
unpinned would have undone the pin everywhere else. Pins are base64 SHA-256
of the DER certificate, supplied with `--dart-define=PINNED_CERT_SHA256` and
never committed; the format is exactly what `openssl` prints, so a
fingerprint can be read off a live host and pasted in. With no pins
configured the app falls back to ordinary CA validation rather than failing
shut, because a dev build against local HTTP has no certificate to pin.
**Configure at least two pins in production** — a single pin turns routine
certificate renewal into an outage only an app-store update can fix, and for
this app an outage means an SOS that does not send. Web builds get a
documented no-op: a browser never hands the chain to page JavaScript.

**Font scale 200% (SRS §5.4, ranked #4).** A new
`test/accessibility/font_scale_test.dart` pumps the component library at 200%
and 300% in both themes. It immediately earned its place: the bottom
navigation overflowed by 1px at 200%. Fixed by clamping the tab label to a
1.3 scale factor — what Material's own `NavigationBar` does — since the icon
and the `Semantics` label carry the meaning and a clipped bar costs a
large-text user far more than a capped caption.

Totals after this session: 538 Flutter tests, 80 backend tests, all green.

### 2026-08-15 — three defects from a real run

Reported from the running app: the Dashboard wouldn't load, error messages
looked broken, and device pairing did nothing.

**Dashboard.** Not a code fault — the dev backend process predated the
`/dashboard/analytics` route and was 404ing it. Restarted with `--reload`
(which `scripts/dev.ps1 backend` uses, and which would have prevented this
outright). Verified end to end against the live server: register → login →
SOS with a location → device register → `GET /dashboard/analytics` → 200
with real aggregated data.

**Toasts had no Material ancestor.** Inserted straight into the `Overlay`,
so every line rendered with Flutter's debug double-underline and no default
text style. Notable as a testing lesson: the component golden wrapped
`SaToastCard` in a `Scaffold` that supplied the missing ancestor, so the
suite was green while the only broken place was the real screen. The
regression test now goes through `showSaToast` itself. Redesigned in the
same pass — severity spine, badged icon, optional headline, dismiss target,
swipe-to-dismiss, error haptic, and one-at-a-time replacement so a burst of
failures can't bury the page.

**Errors accused the wrong thing.** Screens rendered `error.toString()`
directly, and the Dashboard's fixed copy said "Check your connection" for a
404 served over a perfectly good connection — it sent a real debugging
session after the wrong problem. New `describeError` maps any failure to a
headline plus one actionable sentence, keeping "Not available" (404)
distinct from a genuine network error.

**BLE pairing hung instead of failing.** `startScan` caught only
`BleFailure`, but the support check, permission request and adapter probe
all cross a platform channel and can throw something else — a
`MissingPluginException` on a target with no BLE implementation being the
obvious one. Those escaped the controller entirely and left the sheet
spinning on "Scanning…" with nothing on screen. Same hole in
`_attemptConnect`. Unexpected throws now land in a visible failed state that
names the cause.

Totals: 550 Flutter tests, 80 backend tests, all green.

### 2026-08-15 — the pairing crash on web

Follow-up to the entry above. The reported "device pairing does nothing"
turned out to have a second, larger cause than the swallowed errors already
fixed: a full-screen red error page reading
`Unsupported operation: Platform._operatingSystem`.

`canPromptToEnableBluetooth` used `dart:io`'s `Platform.isAndroid`, which
throws on web. Because it is a plain getter read during the pairing sheet's
`build()`, the throw landed inside the render pipeline, where no
controller-level error handling can reach it — the guards added earlier the
same day wrap async controller calls, not `build()`. All platform questions
now go through `defaultTargetPlatform`, and `dart:io` is gone from `lib/`.

**BLE is now reported unsupported on web, on purpose.** Web Bluetooth is a
different shape of API — a browser-drawn chooser opened from a user gesture,
with no free-running scan — so the scan-then-pick flow cannot be driven from
it, and `permission_handler` has no web implementation. The message is
platform-aware, because telling a Chrome user their "phone doesn't support
Bluetooth" is both wrong and a dead end.

Two regression tests: the getter is total across every `TargetPlatform`, and
no library under `lib/` imports `dart:io`. The second was verified by
planting a canary file and watching it fail — a guard nobody has seen fail
is a guard nobody has checked. `flutter build web` also confirmed clean,
which exercises the conditional import behind certificate pinning.

**Testing lesson worth keeping:** three defects this session (the toast's
missing `Material`, this crash, and the swallowed BLE errors) were all
invisible to a green suite because the tests exercised the components in a
friendlier context than the app gives them. Prefer asserting through the
real entry point over the convenient one.

Totals: 553 Flutter tests, 80 backend tests, all green.

### 2026-08-15 — correction: the emergency chain is not connected

Re-auditing §4.3 for a status report turned up the most serious finding of
the day, and a correction to this file's own earlier entry.

**An SOS notifies nobody but the person who pressed it.**
`POST /api/v1/alerts/emergency` creates the incident, stores the location,
broadcasts on the user's own WebSocket and pushes FCM to the user's own
devices. It never reads `emergency_contacts`. There is no SMS code anywhere
— `twilio_*` settings sit in `config.py` unused. The two `sendSms` call
sites in the app are manual "message this contact" buttons, not the alert
path.

**No evidence is captured either.** Nothing imports the `record` package
(declared in `pubspec.yaml`), and no client code calls `/api/v1/media`.

This file previously rated FR-EMG-04 as "🟡 FCM implemented; SMS provider
not configured" and FR-EMG-05 as "✅". Both were wrong, and wrong in the
flattering direction: FCM *is* implemented, but it points at the wrong
person. Corrected to ⛔ above, and promoted to gaps #1 and #2.

Worse, `emergency_repository.dart`'s doc comment asserted that dispatch
"triggers emergency-contact notification and evidence upload server-side" —
a comment describing four unimplemented requirements as done, in the one
feature where being wrong is dangerous. Rewritten to state what the call
actually does.

Nothing here is a regression: this was never built. The reporting was the
defect.

### 2026-08-15 — the emergency chain, connected

Built the fan-out the previous entry identified as gap #1.

`emergency_dispatch.py` notifies contacts in the user's own priority order,
attempts each independently so one bad number cannot stop the rest, and
retries three times with a short backoff (FR-EMG-04 also caps the whole
dispatch at five seconds, so a polite exponential backoff would blow the
budget while someone waits). SMS carries the alert to contacts who have
never installed SafeHer; push is sent additionally when a contact turns out
to have an account. With no Twilio credentials the channel reports itself
unconfigured and logs `skipped_not_configured` — never a fake success.

Message composition holds FR-EMG-05's 160-character budget, and when it must
truncate it drops the evidence link before the location: where someone is
beats what was recorded.

**The larger find was in the app.** The dispatched screen ran a 600ms timer
down the contact list, ticking each one green — with no connection to
whether anything had been sent, and at the time nothing ever was. On the
Emergency screen that is not a cosmetic bug; it told a woman in danger that
her sister had been alerted when no message had left the phone. Contacts are
now marked from the ids the server confirms it delivered to, and three
states are kept distinct: sending, saved-because-offline, and failed.
Reaching nobody raises a banner telling her to call her local emergency
number — the worst outcome on this screen is a user who believes help is
coming and stops trying.

Audit rows record ids only; the message body carries a live location and the
contact row already holds a phone number.

**Still required before this works in production:** Twilio credentials.
Everything is tested against a fake sender; no SMS has reached a real phone.

Totals: 557 Flutter tests, 98 backend tests, all green.

### 2026-08-15 — OneSignal email, and what it does and does not solve

The project has no budget for Twilio, so the ask was to move to OneSignal.

**It does not solve SMS.** OneSignal prices SMS at $3 per 1,000 messages,
and its free-tier SMS trial works by connecting *your own Twilio account* —
it wraps Twilio rather than replacing it. No provider gives SMS away;
carriers charge for it. This is recorded here so the question does not get
re-asked and re-answered.

**It does solve email**, with 10,000 free sends a month. Email is therefore
now a first-class channel in the fan-out, ranked below SMS (nobody watches
an inbox the way they notice a text) but counted as genuinely reaching a
contact, because it is not nothing. For a project with no sponsor it is the
channel that actually works.

Two things had to change before it was usable:

- **The contact form had no email field**, so no contact would ever have had
  an address for the free channel to use. Added, with copy explaining why it
  matters and validation that nudges rather than blocks.
- Adding that field exposed a real layout bug. `showModalBottomSheet` with
  `isScrollControlled` hands the sheet unbounded height, so a form taller
  than the screen lays out past the bottom of it — no overflow stripe, no
  exception, just a save button nothing can reach. Every `SaBottomSheet` is
  now height-capped and internally scrollable.

**A testing lesson, again.** The existing "adding a contact appends it to the
list" test asserted `find.text('Kabir Rao')` after typing that name into a
text field — so it passed whether or not the contact was ever saved. It had
never verified the thing it was named for. Now asserted against the
repository; two of the three new form tests would have had the same hole.
That is the third time this session a green test turned out to be checking a
friendlier situation than the app's.

Totals: 560 Flutter tests, 107 backend tests, all green.

### 2026-08-15 — OneSignal blocked on a domain; SMTP added

The OneSignal credentials arrived and failed with HTTP 401 on every endpoint
and every auth scheme, including a plain `GET /apps/{id}` that has nothing to
do with email.

**A wrong diagnosis, corrected.** I first read the key's app segment in
isolation, found one character off, and called it a paste error. That was
wrong: the key is one continuous base32 stream of `APP_ID + KEY_ID + secret`,
so character 26 legitimately mixes 3 bits of the app id with 2 bits of the
next field. Decoding the whole body confirms the first 16 bytes are exactly
this app's id. The key was fine; my inference was not.

The real blocker is upstream: **OneSignal email requires a sending domain you
own**, verified with SPF/DKIM/DMARC, and explicitly refuses Gmail and Outlook
as senders. The onboarding form asking for a company link was asking for that
domain. A project without one cannot complete the setup at all.

So the channel now also runs over **plain SMTP** — any mailbox with an app
password, no domain, no DNS, no bill. The repo already had a working SMTP
service for sign-up OTPs; it gained an HTML alternative part and an adapter
matching the OneSignal sender's shape. SMTP is tried first, deliberately not
because it delivers better (a personal mailbox sending alert-shaped mail is
more likely to be filtered) but because it is the one that can be configured
today. OneSignal stays wired and becomes the better option once a domain
exists.

`SETUP.md` carries the Gmail app-password walkthrough.

Totals: 560 Flutter tests, 112 backend tests, all green.

### 2026-08-15 — emergency email delivering, verified live

An SOS now reaches a real inbox. Proven against the running backend, not
just in tests: `contacts_total 1, contacts_notified 1`, one id in
`contacts_reached`, and an `email sent` row in the notification log.

Two defects surfaced on the way.

**Port 465.** Delivery failed with a bare "timed out" despite correct
credentials. A port scan explained it: 25 and 587 both time out on this
network while 465 connects — a common consumer-ISP anti-spam policy. The
service only knew how to STARTTLS, so it could not use the one port that was
open. It now speaks implicit TLS when the port calls for it, inferred from
the port rather than adding another setting to get wrong.

**The test suite was reading the developer's `.env`** — and therefore
**sending real email**. Registration emails a verification code, so every
test that created a user had been mailing made-up `@safeherapp.com`
addresses for as long as SMTP was configured locally. The same leak flipped
`require_email_verification` on (it follows deliverability) and made 18
tests fail on a 403 that had nothing to do with the code under test.
`tests/conftest.py` now blanks every outbound channel before any test module
imports the app.

That is the fourth time this session a green suite turned out to be testing
a different situation than the app's — and the first where the leak reached
outside the process.

Totals: 560 Flutter tests, 115 backend tests, all green.

### 2026-08-15 — the contact an SOS could not reach

Caught by the project owner, not by a test: with SMS unconfigured, email is
the only channel that reaches an ordinary person — so a contact saved with
only a phone number could not be reached at all. The app said nothing, and
there was no way to add an address afterwards. A user would have seen a
normal saved contact and believed her sister would be alerted.

Fixed in three parts:

- **`GET /api/v1/alerts/channels`.** The client cannot infer which channels
  work; that depends on server-side credentials it never sees. The endpoint
  reports `sms`/`email`/`push` plus `email_requires_address` — true when
  email is the only channel reaching a contact, so an address is the
  difference between reachable and not.
- **A warning that names the cause and the remedy**, shown only on contacts
  that genuinely cannot be reached. With SMS available a phone number is
  enough and no warning appears; while the channel answer is loading the UI
  assumes everything works, so nothing flashes and retracts.
- **Contacts are editable.** Tapping a card reopens the sheet prefilled, so
  adding a missing address is one field.

Two test-fixture bugs surfaced on the way: the fake contacts repository
stored whatever list it was handed, so a `const` list made every mutation
throw inside an async gap and vanish; and the channels provider resolves a
frame after the list mounts, which a single pump misses.

Totals: 564 Flutter tests, 118 backend tests, all green.

### 2026-08-15 — evidence capture, end to end

Gap #2 closed. An SOS now records audio and stores it encrypted.

**Storage.** The existing media router only signed Cloudinary uploads, which
needs an account this project does not have — so evidence stores on the
project's own backend instead, the same reasoning that put emergency email
on plain SMTP. AES-256-GCM at rest, with the key derived from
`JWT_SECRET_KEY` when no dedicated one is set: deriving rather than falling
back to plaintext, because an "encryption optional if unconfigured" path
means the one deployment nobody configured is the one storing assault
recordings in the clear. GCM authenticates too, so an altered file is
refused rather than served. Nothing is reachable by URL — retrieval is
authenticated and ownership-checked, and unknown vs. someone-else's ids both
return 404 so a stranger cannot probe for real incidents.

**Capture.** Audio only. Video needs a camera pointed at something useful,
which a phone in a pocket is not, and it costs battery and upload time an
emergency cannot spare. Recording starts with the countdown, ahead of
FR-EMG-06's one-second requirement, and covers the seconds spent deciding.

**Honest failure.** A refused microphone never interrupts someone
mid-emergency; the alert goes out regardless and the outcome is reported
afterwards, with a distinct state for each case. Marking safe deletes the
recording (FR-EMG-08), as does an offline alert with no incident to attach
to. The local file is deleted as soon as its bytes are read.

Three defects found on the way: `python-multipart` was missing from
`requirements.txt` so every upload would have failed on a fresh install; the
evidence directory was not gitignored; and the recorder was read through
`ref` inside `dispose()`, which throws and would have left the microphone
open on any screen exit during a recording.

The `dart:io` guard was extended rather than weakened: `*_io.dart` files are
exempt as the native half of a conditional export, with a second test
asserting nothing imports one directly.

Totals: 576 Flutter tests, 140 backend tests, all green.

### 2026-08-15 — contact verification

FR-EMG-10 closed. `confirmed` had been a hardcoded `true` in the client's
JSON mapping, so the app displayed a confirmation nobody had performed.

SafeHer now emails the contact a six-digit code and asks them to pass it to
the person who added them. The contact needs no account and no app — asking
a sister to install software before she can be an emergency contact is how
contact lists end up empty — and the email explains who added them and why,
because an unexplained code from an unknown sender reads as phishing.

Two decisions pinned as contract, since both are easy to "fix" the wrong way
later:

- **An unverified contact is still notified.** Verification says which
  entries to double-check; it is not a gate on getting help, because a
  possibly-wrong address beats no address when someone is in danger.
- **Changing an address drops its verification.** A tick earned at one
  address says nothing about another, and keeping it would hide exactly the
  typo this catches.

Also enforced the ten-contact cap the SRS specifies and nothing implemented.

Totals: 580 Flutter tests, 159 backend tests, all green.

### 2026-08-15 — share links and the last unpinned channel

Two gaps closed, plus a fix for the error message that had been misleading
me for three sessions.

**Share links (FR-RPT-06).** An incident can now reach someone with no
SafeHer account — a police officer, a lawyer, a parent — through a
token-only link that expires in seven days and can be revoked sooner. The
token is 32 bytes of randomness, shown once, stored only as a hash. The
shared view carries the incident, its location and its evidence and nothing
about the account. Evidence still streams through the server, decrypted per
request, precisely so that revocation and expiry can actually withdraw
access; a permanent URL handed out once never could. Unknown, revoked and
expired links answer identically, because telling them apart would confirm
to a stranger that a link was once real.

**WebSocket pinning.** The HTTP API had been pinned for a while; the socket
carrying threat scores and emergency broadcasts was still on plain CA trust,
which left the easier target unpinned. `WebSocketChannel.connect` exposes no
certificate, so the socket is now built from an `HttpClient` with no trusted
roots — every chain fails, every certificate reaches
`badCertificateCallback`, and the pin becomes the sole trust anchor. That
discards the CA's checks, so validity-window and pin checks are re-applied
by hand.

**A 404 meant two different things.** FastAPI answers an unknown *route*
with a generic `{"detail": "Not Found"}`, while every handler here answers a
missing *record* specifically. The app rendered both as "That couldn't be
found", which sent a real debugging session after a contact that existed
perfectly well; the truth was a backend nobody had restarted. Now the
generic form reads as "Server needs updating — restart the backend".

**A mistake worth recording:** I overwrote `fastapi_app/deps.py` while
extracting a shared dependency, destroying its existing `SettingsDep`. Git
had it; the file is now additive-only. Read before writing, including files
that look new.

Totals: 584 Flutter tests, 174 backend tests, all green.

### 2026-08-15 — PDF export, evidence follow-up, and a verifiable SRS

**FR-RPT-03.** "Forensic-grade" is the load-bearing word: a PDF that merely
restates what the app shows is a printout. Every evidence file is listed
with the SHA-256 of the exact bytes SafeHer holds, plus a document hash over
the report's facts, so a reader handed a recording separately can re-hash it
and compare. The page says outright that this is an integrity check and not
a signature — overstating what a hash proves is worse than omitting it. The
recording itself is never embedded, and a recording that cannot be decrypted
is omitted rather than given a placeholder hash, because a chain of custody
with an invented link is worse than one that is honestly short.

**FR-EMG-05, the half that could not travel in the alert.** The evidence URL
does not exist when the alert fires — the recording is still being made.
Holding the alert back until it did would trade the requirement that matters
for one that does not, so the URL follows in a second email carrying a share
link. Email only: a second SMS saying "there is also a recording" is not
worth what the first one is worth.

**A verifiable SRS.** Auditing compliance automatically for the first time
reported 20 of 37 requirements as unimplemented — almost all of them built,
just never linked to the requirement they satisfy. The gap was traceability,
not code, and acting on the raw number would have sent a rewrite after
features that already worked. `TRACEABILITY.md` now maps every requirement
to its implementation, and a test enforces the map: nothing can go missing
from it, no path can rot, and "not built" cannot sit next to a file path.

Totals: 584 Flutter tests, 195 backend tests, all green.
