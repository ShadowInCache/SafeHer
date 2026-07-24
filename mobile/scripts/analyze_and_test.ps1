$ErrorActionPreference = "Stop"

flutter pub get
flutter analyze lib/main.dart lib/app
flutter test
