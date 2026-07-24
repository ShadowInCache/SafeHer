# SafeHer Mobile Deployment

## Build Commands

### Android APK

```bash
cd SafeHer/mobile
flutter build apk --release --dart-define APP_FLAVOR=production
```

### Android App Bundle

```bash
flutter build appbundle --release --dart-define APP_FLAVOR=production
```

### iOS

```bash
flutter build ios --release --dart-define APP_FLAVOR=production
```

## Signing

- Android: configure keystore and `key.properties` before production builds.
- iOS: configure signing certificates and provisioning profiles in Xcode.

## Production Checklist

- Replace development endpoints with production URLs.
- Disable cleartext traffic for Android if backend is HTTPS-only.
- Verify all permission prompts and privacy-policy references.
- Validate Firebase Crashlytics and push notification delivery.
- Run full test suite and smoke test on physical devices.

## CI/CD

A baseline workflow is available at `.github/workflows/mobile-ci.yml`.
It runs dependency resolution, static analysis, and tests for every change under `SafeHer/mobile`.
