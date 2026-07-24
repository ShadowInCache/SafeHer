# SafeHer Mobile Cleanup Report (2026-04-20)

## Scope
- Audited active Flutter runtime graph rooted at `lib/main.dart`.
- Verified Flutter/Firebase integration and backend connectivity prerequisites.
- Performed safe cleanup by archiving legacy code instead of deleting uncertain files.

## Actions Completed

### 1) Firebase Setup and Verification
- Generated `lib/firebase_options.dart` via FlutterFire for project `safeher-2a1f2`.
- Updated Firebase initialization to use platform options.
- Verified Android Firebase config exists at `android/app/google-services.json`.

Refactored file:
- `lib/app/core/firebase/firebase_support.dart`

### 2) Legacy Code Isolation (Safe Archive)
Moved duplicate legacy code trees out of the runtime source path (`lib/`) into:
- `deprecated/legacy_flutter_tree/lib/core`
- `deprecated/legacy_flutter_tree/lib/data`
- `deprecated/legacy_flutter_tree/lib/presentation`
- `deprecated/legacy_flutter_tree/lib/services`

Reason:
- The active app is built from `lib/app/**` and `lib/main.dart`.
- Legacy trees created duplicate architecture and maintenance overhead.
- Archiving preserves rollback ability while removing dead runtime surface.

### 3) Dependency Cleanup
Updated `pubspec.yaml` by removing dependencies not used by active runtime/test import graph.

Removed dependencies:
- `cupertino_icons`
- `provider`
- `dio`
- `intl`
- `flutter_local_notifications`
- `json_annotation`
- `geolocator`

Removed dev dependencies:
- `build_runner`
- `json_serializable`
- `mocktail`

### 4) Analyzer Scope Cleanup
Updated `analysis_options.yaml`:
- Excluded archived code with `deprecated/**` to prevent stale/legacy files from affecting CI analyzer.

## Validation Results
- `flutter pub get` completed successfully after dependency trim.
- `flutter analyze` completed with **No issues found**.
- `flutter test` completed with **All tests passed**.

## Architectural Findings Summary
- Current codebase can be stabilized in Flutter if hardware integrations are modularized and moved behind native platform channels/plugins.
- BLE, high-frequency sensor ingestion, camera/mic processing, and resilient Android background execution should be Android-native (Kotlin foreground services + WorkManager), exposed to Flutter through a narrow plugin API.
- Existing controller `lib/app/shared/state/safety_controller.dart` is a God-object and should be decomposed by feature/use-case boundaries.

## Risk Notes
- iOS Firebase app is registered and `firebase_options.dart` includes iOS config, but `ios/Runner/GoogleService-Info.plist` is not present in this Windows-based setup pass and should be generated/verified on macOS for iOS release readiness.

## Rollback Plan
- Restore archived code by moving folders back from `deprecated/legacy_flutter_tree/lib/*` into `lib/`.
- Re-add removed packages from VCS history if any archived module is reinstated.

