# SafeHer Mobile

The Flutter client. 889 tests, zero analyzer issues.

Its job is narrow and load-bearing: **get an alert out.** Everything here —
the screens, the BLE link, the offline queue — exists to serve that, and the
app never tells a user something worked when it didn't.

> Repo-wide orientation lives in the [root README](../README.md).
> Setup, environment variables and troubleshooting: [docs/SETUP.md](../docs/SETUP.md).

---

## Quick start

```bash
flutter pub get
flutter run                  # talks to the deployed backend by default
```

The default `API_BASE_URL` is the **deployed** backend, not localhost. A
release build that quietly falls back to `127.0.0.1` is one that cannot work
on a real phone, and the failure looks like a network problem rather than a
misbuild.

```bash
# Android emulator → a backend running on the host machine
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000/api/v1

# No backend at all — fixture data, for UI work
flutter run --dart-define=USE_MOCK_API=true
```

---

## Build-time configuration

Every switch lives in [`lib/core/config/app_config.dart`](lib/core/config/app_config.dart),
and each one is documented there with the reasoning behind its default.

| `--dart-define` | Default | What it does |
|---|---|---|
| `API_BASE_URL` | deployed Render backend | Base URL for all REST calls |
| `USE_MOCK_API` | `false` | Swap every repository for a fixture-backed one; no network |
| `USE_FIREBASE_AUTH` | `true` | `false` falls back to backend-native email/password auth — no Google, Apple or guest sign-in on that path |
| `PINNED_CERT_SHA256` | *(empty)* | Base64 SHA-256 of allowed DER certificates, comma-separated |
| `PINNED_CERT_ISSUERS` | `O=Google Trust Services` | Allowed certificate issuers. Issuer pinning, not leaf pinning — Render rotates its certificate roughly every 90 days, and a leaf pin would strand every installed copy of the app mid-rotation |
| `EMERGENCY_HELPLINE` | `112` | The national emergency number the SOS screen dials. India's ERSS by default; a hardcoded 112 shown to someone in the US is a wrong number at the worst moment |

---

## Layout

```text
lib/
├── main.dart              Bootstrap: Firebase, DI, ProviderScope, MaterialApp.router
├── core/                  Cross-cutting machinery, no feature owns it
│   ├── background/          Foreground service — keeps detection alive off screen
│   ├── detection/           What is actually detecting, and its honest limits
│   ├── security/            App lock, certificate pinning
│   ├── evidence/            Recording + AES-256-GCM encryption before upload
│   ├── offline/             Action queue that replays when connectivity returns
│   ├── sensors/             Shake detector
│   ├── voice/               On-device command recognition
│   ├── local/               Hive wrappers (LocalKeyValueStore, preferences)
│   ├── network/             Dio client, interceptors, pinning
│   ├── location/, session/, connectivity/, biometrics/, platform/
│   ├── router/              GoRouter table — all navigation goes through it
│   ├── theme/               Design tokens: colour, type, spacing, radius
│   ├── animations/          Reduced-motion-aware helpers
│   └── di/                  get_it setup
├── features/              One folder per domain, each data/ → domain/ → presentation/
│   ├── auth/  home/  dashboard/  devices/  monitoring/  emergency/
│   └── reports/  search/  contacts/  profile/  settings/  safety/
└── shared/
    ├── components/          SaCard, SaButton, SaIcon, Sa3DModelViewer, …
    └── models/              Models used across features
```

`test/` mirrors `lib/` exactly. `test/test_utils/` holds the fakes —
`FakeBleService`, `FakeForegroundService`, `FakeKeyValueStore`,
`FakeAuthRepository`, `FakeSafetyRepository`.

---

## House rules

Stricter than most Flutter projects, and deliberately so. Full detail in
[docs/CONTRIBUTING.md](../docs/CONTRIBUTING.md).

- **Riverpod only.** No `setState`.
- **GoRouter only.** No direct `Navigator.push`.
- **Custom vector icons** (`SaIcon` via `CustomPainter`). No Material defaults.
- **A screen isn't done** until it has a widget test *and* a golden in both themes.
- **No placeholder screens or `TODO` widgets** get committed.

Typography is **Archivo**, with **JetBrains Mono** for data. Inter is the
default face of nearly every generated app; the interface had no voice before
a word was read.

---

## The glove

A paired SafeHer glove runs an XGBoost model on the ESP32 and notifies its
classification over BLE — **no server in the path.** The app votes on those
classifications and opens the ordinary SOS countdown.

- Wire contract: [`lib/features/devices/domain/glove_protocol.dart`](lib/features/devices/domain/glove_protocol.dart)
- The vote: [`lib/features/devices/domain/glove_threat_detector.dart`](lib/features/devices/domain/glove_threat_detector.dart)
- Where it runs: [`lib/features/safety/data/glove_auto_trigger.dart`](lib/features/safety/data/glove_auto_trigger.dart)

Two design points worth knowing before changing any of it:

**The vote does not live in a widget.** Flutter stops pumping frames when the
app leaves the screen, so anything in a `build()` method stops running — which
is how automatic detection was once silently conditional on the app being
looked at. It runs in a `keepAlive` provider driven by `ref.listen`, and every
test for it runs against a bare `ProviderContainer` with no widget tree.

**Two hits in five seconds, not one.** A single `FALL` is a glove dropped on a
table or a sleeve caught on a door. A feature that cries wolf gets switched
off, and then it protects nobody.

Flashing firmware or collecting training data is a separate procedure — see
[glove/README.md](../glove/README.md).

---

## Testing

```bash
flutter test                    # 889 tests
flutter analyze                 # 0 issues
flutter test --update-goldens   # after a deliberate visual change
```

Goldens render in both light and dark. `clock` is injected so time-of-day
never makes a golden flake.

Two guard tests are worth knowing about before they fail on you:

- **`dart:io` is banned anywhere web-reachable under `lib/`.** It throws in a
  browser and shows up in no VM test. Use `defaultTargetPlatform` / `kIsWeb`,
  or a conditional import with an `_io.dart` half.
- **The BLE wire contract is asserted against the firmware's literal
  payloads.** If the ESP32's format drifts, `glove_protocol_test.dart` is what
  tells you.

Local scripts: `scripts/run_dev.ps1`, `scripts/analyze_and_test.ps1`,
`scripts/build_release.ps1`.

---

## Platform status

**Android** — the primary target. `flutter build apk --release` produces a
release APK with no errors. Verified on real hardware: the app lock, and the
BLE scan/connect path.

**Web** — a supported target as of 2026-08-30. `flutter build web --release`
compiles clean. Two things behave differently there and are worth knowing
before shipping a web build:

- **No glove.** `flutter_blue_plus` has no web implementation, so BLE pairing
  and everything downstream of it — the classification feed, the vote, the
  foreground service — do not exist on web. `DetectionSources` already reports
  what is actually detecting, so the UI says so rather than implying a glove
  could connect.
- **`FlutterSecureStorage` on web is not a Keychain.** It falls back to
  browser storage, which is a weaker guarantee than the Android Keystore. Treat
  a web session as lower-trust than a phone.

The `dart:io` guard test is what keeps the web build working; it was written
before web was a target and is the reason enabling one took no porting.

**iOS** — out of scope. `GoogleService-Info.plist` and the `REVERSED_CLIENT_ID`
URL scheme are registered and no iOS build has ever run; the project is not
targeting it.

---

## What is honestly not finished

- **No glove has ever been paired with the app.** The glove *firmware* was
  validated on a real ESP32-C3 on 2026-09-10 (sensor, sampling, on-device
  inference), but the app side — the BLE layer, written against the real
  `flutter_blue_plus` API — still runs every test against `FakeBleService`. The
  end-to-end path from a physical ESP32 to a woken screen is unverified.
- **The foreground service is unverified on a device.** It builds, the service
  is in the merged manifest with the `connectedDevice|location` type, and the
  UI only claims the pocket case works when the platform says the service
  actually started. Nobody has put a phone in a pocket and fallen over yet.
- **The phone-side detectors are wired but unproven on a real feed.** The weapon
  model runs on-device (Android) and the audio phrase classifier runs over
  platform ASR, but neither has met a real glasses stream or real distress
  speech. Crucially, the app still **never invents a threat score from the
  phone's own accelerometer** — that shortcut would alert every emergency
  contact on a dropped phone, and each false alarm spends the credibility the
  real alert depends on. Without a wearable, the phone's honest trigger is the
  deliberate shake gesture, which opens the countdown rather than dispatching.
