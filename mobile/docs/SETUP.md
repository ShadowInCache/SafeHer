# SafeHer Mobile Setup

## Prerequisites

- Flutter stable SDK
- Android Studio + Android SDK
- Xcode 15+ (for iOS builds)
- CocoaPods (`sudo gem install cocoapods`)
- A Firebase project (Auth, Firestore, Messaging, Crashlytics enabled)

## 1. Install Dependencies

```bash
cd SafeHer/mobile
flutter pub get
```

## 2. Configure Firebase

1. Create Android and iOS apps in Firebase console.
2. Download `google-services.json` and place it in `android/app/`.
3. Download `GoogleService-Info.plist` and place it in `ios/Runner/`.
4. Ensure Firebase services are enabled in your project.

## 3. Configure Runtime Endpoints

Use `--dart-define` values when running:

```bash
flutter run \
  --dart-define APP_FLAVOR=development \
  --dart-define API_BASE_URL=http://10.0.2.2:5000/api/v1 \
  --dart-define WS_BASE_URL=ws://10.0.2.2:8765/ws \
  --dart-define MQTT_HOST=10.0.2.2 \
  --dart-define MQTT_PORT=1883
```

## 4. Validate Build Health

```bash
flutter analyze lib/main.dart lib/app
flutter test
```

## 5. Platform Permission Notes

- Android permissions are declared in `android/app/src/main/AndroidManifest.xml`.
- iOS privacy descriptions and background modes are declared in `ios/Runner/Info.plist`.

Review and tailor these strings for your legal/compliance requirements before release.
