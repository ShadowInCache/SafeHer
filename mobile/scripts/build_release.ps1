param(
  [ValidateSet("apk", "appbundle", "ios")]
  [string]$Target = "apk"
)

$ErrorActionPreference = "Stop"

switch ($Target) {
  "apk" {
    flutter build apk --release --dart-define APP_FLAVOR=production
  }
  "appbundle" {
    flutter build appbundle --release --dart-define APP_FLAVOR=production
  }
  "ios" {
    flutter build ios --release --dart-define APP_FLAVOR=production
  }
}
