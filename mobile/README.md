# SafeHer Mobile App

SafeHer is a cross-platform Flutter app for proactive and emergency personal safety.
It combines wearable telemetry, AI-informed threat scoring, secure evidence capture,
and guardian/emergency communication in one mobile experience.

## Stack

- Flutter + Dart (Android + iOS)
- Riverpod state management
- Firebase Auth, Messaging, Firestore, Crashlytics
- REST + WebSocket + MQTT realtime channels
- BLE wearable pairing (glove + glasses)
- SQLite offline cache + secure storage
- AES evidence encryption + biometric unlock

## Project Layout

- `lib/app/core`: environment, networking, services, theme, localization
- `lib/app/features`: feature-oriented presentation + data modules
- `lib/app/shared`: domain models, global providers, shared widgets
- `test`: unit/widget/api/realtime/offline test suites
- `integration_test`: app-level smoke integration scenarios

## Quick Start

1. Install Flutter stable and platform toolchains.
2. From `SafeHer/mobile`, run:
	- `flutter pub get`
	- `flutter analyze lib/main.dart lib/app`
	- `flutter test`
3. Run on device/emulator:
	- `flutter run --dart-define APP_FLAVOR=development`

Integration smoke tests:

- `flutter test integration_test/safeher_smoke_test.dart -d <android-emulator-id>`
- `flutter test integration_test/safeher_smoke_test.dart -d <ios-simulator-id>`

## Runtime Defines

You can override environment values with `--dart-define`:

- `APP_FLAVOR`: `development` | `staging` | `production`
- `API_BASE_URL`: backend REST API base URL
- `WS_BASE_URL`: websocket base URL
- `MQTT_HOST`: MQTT broker host
- `MQTT_PORT`: MQTT broker port

Example:

```bash
flutter run \
  --dart-define APP_FLAVOR=staging \
  --dart-define API_BASE_URL=https://api.safeher.example/api/v1 \
  --dart-define WS_BASE_URL=wss://api.safeher.example/ws \
  --dart-define MQTT_HOST=mqtt.safeher.example \
  --dart-define MQTT_PORT=8883
```

## Scripts

- `scripts/run_dev.ps1`: run app with development defines
- `scripts/analyze_and_test.ps1`: lint + unit/widget test pipeline
- `scripts/build_release.ps1`: production release build helpers

## Documentation

- `docs/SETUP.md`: local setup and prerequisites
- `docs/ARCHITECTURE.md`: module and data flow overview
- `docs/DEPLOYMENT.md`: release and CI/CD notes

## CI

GitHub Actions workflow: `.github/workflows/mobile-ci.yml`

Pipeline checks:

- dependency resolution
- static analysis
- test suite execution
