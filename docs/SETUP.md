# Setup

## Prerequisites

- **Python 3.11+** — backend and ML training scripts
- **Flutter 3.x** (Dart `>=3.8.0 <4.0.0`, see `mobile/pubspec.yaml`) — mobile app
- **Docker + Docker Compose** — if you want the full local stack (Postgres, Redis,
  Mosquitto) instead of running the backend against a bare SQLite file
- **A Supabase project** — optional, only needed for the events-archive feature

## 1. Clone and install

```bash
git clone https://github.com/ShadowInCache/SafeHer.git
cd SafeHer
pip install -r requirements.txt
```

`requirements.txt` covers three concerns in one file: the current FastAPI backend, the
and the ML training pipeline
for model training. You don't need the ML stack (`torch`, `ultralytics`, `librosa`, ...)
just to run the backend — see [DEPENDENCIES.md](DEPENDENCIES.md) if you want to trim
your local install.

## 2. Environment variables

```bash
cp .env.example .env
```

Then fill in real values. Grouped by concern:

| Group | Variables | Notes |
|---|---|---|
| Core | `API_HOST`, `API_PORT`, `DEBUG`, `LOG_LEVEL` | Defaults work for local dev (`API_PORT=5000`) |
| Database | `DATABASE_URL` | Defaults to SQLite (`sqlite:///./safeher.db`) if unset; use a `postgresql://` URL for Postgres |
| Supabase | `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY` | Only required if you use the events-archive feature. **Never commit real values** — see [SECURITY.md](SECURITY.md) |
| Redis | `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` | Used by the event-processing pipeline |
| MQTT | `MQTT_HOST`, `MQTT_PORT`, `MQTT_USERNAME`, `MQTT_PASSWORD` | Needed if you're testing against real/simulated device firmware |
| Auth | `JWT_SECRET_KEY`, `JWT_ISSUER`, `JWT_AUDIENCE`, `ACCESS_TOKEN_EXPIRE_MINUTES`, `REFRESH_TOKEN_EXPIRE_DAYS` | `JWT_SECRET_KEY` **must** be a strong, non-default value in staging/production — `fastapi_app/config.py` refuses to start otherwise |
| Notifications | `FCM_SERVER_KEY` | Push to the user's own devices |
| Emergency email | `SMTP_*` **or** `ONESIGNAL_*` | The channel that works with no budget. SMTP is tried first — see below |
| SMS | `TWILIO_*` | Optional and **not free**. Unset, an SOS reports SMS as unconfigured instead of pretending to send. OneSignal is not a way around this: its free-tier SMS connects *your own* Twilio account |

### Emergency email with no domain and no budget

An SOS reaches emergency contacts by email. Two ways to configure it, and
the dispatcher picks whichever is available (SMTP first):

**SMTP — works today, needs nothing you don't already have.** Any mailbox
with an app password. For Gmail:

1. Turn on 2-Step Verification on the Google account.
2. Go to <https://myaccount.google.com/apppasswords> and create an app
   password named "SafeHer".
3. Put it in `.env` (never committed — CI fails the build if a `.env` is
   ever tracked):

```env
SMTP_HOST=smtp.gmail.com
# 465, not 587: many consumer ISPs block 25 and 587 as an anti-spam measure
# while leaving 465 open. If mail "times out" with correct credentials, this
# is almost always why. TLS style is inferred from the port.
SMTP_PORT=465
SMTP_USE_TLS=true
SMTP_USERNAME=you@gmail.com
SMTP_PASSWORD=<the 16-character app password>
SMTP_FROM_EMAIL=you@gmail.com
SMTP_FROM_NAME=SafeHer
```

Gmail allows roughly 500 messages a day, which is far beyond what emergency
contacts will use. The same settings also power sign-up OTP email.

**OneSignal — better deliverability, but needs a domain.** Its free tier
covers 10,000 emails a month, but sending requires a domain you own with
SPF, DKIM and DMARC records; Gmail and Outlook addresses are explicitly
refused as senders. Worth moving to once SafeHer has a domain. Until then
the OneSignal path cannot be configured at all, so use SMTP.
| Storage | `CLOUDINARY_*` | Optional — `/api/v1/media/sign-upload` returns 400 if unset |
| Maps | `GOOGLE_MAPS_API_KEY` | Used by the mobile app |
| CORS | `ALLOW_ORIGINS` | Comma-separated list |

## 3. Run the backend

**Option A — Docker Compose (recommended, matches production topology):**
```bash
python manage.py start      # brings up Postgres, Redis, Mosquitto, event processor
python manage.py status
python manage.py logs
python manage.py stop
```

**Option B — bare backend, no Docker (fastest inner loop):**
```bash
python app.py
```
This talks to whatever `DATABASE_URL` points at (SQLite by default) and warns —
without failing — if Redis or the event processor aren't reachable.

### Database schema

Migrations are the single source of truth and run automatically on startup, so
there is normally nothing to do. To drive them by hand:

```bash
python -m alembic upgrade head    # note: `python -m`, not bare `alembic`
python -m alembic current
```

Use `python -m alembic` rather than the `alembic` console script -- the script
may resolve to a different interpreter than the one running the backend, and
will then fail on unrelated dependency versions.

A database created before migrations existed (schema built by `create_all`, no
`alembic_version` table) is adopted automatically: startup stamps it at head and
continues, leaving existing rows untouched.

### Pointing at Supabase Postgres

Set `DATABASE_URL` to the Supabase connection string and migrations plus the app
follow it:

```bash
DATABASE_URL=postgresql://postgres:<db-password>@db.<project-ref>.supabase.co:5432/postgres?sslmode=require
```

The password is the **database** password from Supabase → Project Settings →
Database, which is not the same as `SUPABASE_SECRET_KEY` (an API key, which
cannot open a Postgres connection). `sslmode=require` is translated to the
argument asyncpg expects, so the libpq-style URL Supabase gives you works as-is.

Verify it's up:
```bash
curl http://localhost:5000/api/v1/health
```

## 4. Run the mobile app

```bash
cd mobile
flutter pub get
flutter run                     # picks a connected device/emulator
flutter run -d chrome           # or run in a browser
flutter run -d web-server --web-port=8765   # headless web server, for automated screenshots
```

The mobile app defaults to the real `fastapi_app` backend (`AppConfig.useMockApi` in
`mobile/lib/core/config/app_config.dart`) — every feature (auth, contacts, emergency,
devices, dashboard, reports, live monitoring, BLE pairing, settings) has a real backend
path now, so start the backend first (step 3 above) or `flutter run` will show
connection-error states. To explore the UI on fixture data without a backend running,
pass `--dart-define=USE_MOCK_API=true`.

## 4a. Accounts and sign-in

Firebase Authentication **is enabled** on the `safeher-2a1f2` project, with the
Google, Phone and Anonymous providers plus Email/Password turned on. So the app
defaults to the Firebase path (`AppConfig.useFirebaseAuth`, default `true`).
Firebase collects the credential; `fastapi_app` still owns the account, because
every successful sign-in is exchanged for a backend JWT at
`POST /api/v1/auth/firebase/exchange`.

Verify the providers yourself at any time:

```bash
KEY=<web-api-key from mobile/lib/firebase_options.dart>
# Email/Password
curl -s -X POST "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$KEY"   -H 'Content-Type: application/json'   -d '{"email":"probe@example.com","password":"TestPass123!","returnSecureToken":true}'
# Anonymous
curl -s -X POST "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$KEY"   -H 'Content-Type: application/json' -d '{"returnSecureToken":true}'
```

`CONFIGURATION_NOT_FOUND` would mean Authentication is switched off for the
project entirely; `OPERATION_NOT_ALLOWED` means that one provider is disabled.

### Fallback: backend-native auth

```bash
flutter run --dart-define=USE_FIREBASE_AUTH=false
```

Email/password is then served directly by `fastapi_app` with no console
dependency. Google, Apple and guest sign-in are unavailable on that path, since
they need a real identity provider. The backend implements SRS section 4.1
either way: FR-AUTH-01 (emailed OTP), FR-AUTH-04 (15-minute access / 30-day
refresh), FR-AUTH-06 (password change revokes other sessions), FR-AUTH-07
(5 failures lock for 15 minutes), FR-AUTH-08 (30-day deletion grace).

### Guest mode

The Anonymous provider backs "Continue as guest" on the login screen: it reaches
the SOS button without an account, which matters when help is needed now. The
backend still provisions a real account keyed to the Firebase uid, with a
synthetic address (`<uid>@anonymous.safeherapp.com`), so contacts and incidents
persist. An anonymous account **cannot be recovered on another device**, which is
why guest mode is the last option on the screen rather than the headline one.

### Clock skew

Firebase mints tokens against Google's clock. A machine running even a second
behind sees freshly-issued tokens rejected as "Token used too early", which
presents as intermittent, unreproducible sign-in failures. The backend allows
`CLOCK_SKEW_TOLERANCE_SECONDS` (30s) of leeway in
`fastapi_app/services/firebase_auth.py`.

### Email verification is enforced only when it can be delivered

`REQUIRE_EMAIL_VERIFICATION` is unset by default, so verification is enforced
exactly when SMTP is configured. Without a mail server, forcing it on would
create accounts that can never sign in.

- **No SMTP** -- sign-up completes and signs the user straight in.
- **SMTP configured** (`SMTP_HOST` + `SMTP_FROM_EMAIL`) -- verification turns on
  automatically; `POST /auth/verify-email` completes it.
- **Development without SMTP** -- the register response carries `debug_code` so
  the flow can be finished locally. Only when `ENVIRONMENT=development` *and*
  SMTP is absent.

Forgot-password uses the same mechanism (`/auth/password-reset/request` and
`/confirm`). Reset codes and verification codes carry distinct purposes, so
neither is redeemable as the other.

## 4b. Firebase sign-in (optional -- needed for Google and Apple)

This section applies only when you build with
`--dart-define=USE_FIREBASE_AUTH=true`. Firebase *collects* the credential and
`fastapi_app` still *owns* the account: every successful Firebase sign-in is
exchanged for a backend JWT at `POST /api/v1/auth/firebase/exchange`, which
auto-provisions the user on first sign-in. Both halves have to be configured or
sign-in fails.

Enabling Authentication in the console is the prerequisite for everything below
-- see section 4a for how to confirm whether it is enabled.

The repo already contains a real Firebase project (`safeher-2a1f2`):
`mobile/lib/firebase_options.dart` and `mobile/android/app/google-services.json`.
What is **not** configured — and cannot be, from code alone — is the console side.

### Backend

Set the project id so ID tokens are validated against the right audience.
Without it, tokens are accepted with no audience check, meaning a token minted by
*any* Firebase project would be honoured:

```bash
# .env at the repo root
FIREBASE_PROJECT_ID=safeher-2a1f2
```

### Enable the sign-in providers

Firebase console → **Authentication → Sign-in method**, enable:

| Provider | Needed for |
|---|---|
| Email/Password | Sign-up and email login |
| Google | "Continue with Google" |
| Phone | The OTP step after sign-up (optional — see below) |

If a provider is disabled, Firebase returns `operation-not-allowed` and the app
surfaces "This sign-in method isn't enabled for this app yet."

### Android Gradle wiring (already done)

Firebase's Android setup guide asks you to add the Google services Gradle plugin.
In a Flutter project `flutterfire configure` has already done this, in the
Flutter-idiomatic place rather than the one the guide names:

| Guide says | This project |
|---|---|
| plugins block in root `build.gradle.kts` | `android/settings.gradle.kts` plugins block |
| `id("com.google.gms.google-services")` in app module | `android/app/build.gradle.kts` — present |
| `google-services.json` in app module | `android/app/google-services.json` — present |

**Do not add the Firebase BoM or `firebase-analytics` by hand.** That step in the
guide is for native Android apps. Here the FlutterFire packages
(`firebase_core`, `firebase_auth`, `firebase_messaging`) declare their own native
dependencies at versions known to work together; adding the BoM on top invites
version conflicts. To add a Firebase product, add its Flutter package to
`pubspec.yaml` instead.

Two changes were made on 2026-08-15:

- `com.google.gms.google-services` bumped 4.3.15 → 4.5.0, the version current
  Firebase docs specify and the one tested against Android Gradle Plugin 8.x
  (this project uses AGP 8.11.1 with Gradle 8.14).
- The `com.google.firebase.crashlytics` plugin was **removed**. It was applied in
  `app/build.gradle.kts` while `firebase_crashlytics` was never in
  `pubspec.yaml` — a Gradle plugin with no SDK behind it. Re-add both together
  if you want crash reporting.

> **Unverified by a build.** There is no Android SDK on the development machine,
> so no Gradle build has been run against these changes. The files were checked
> structurally only. If `flutter build apk` fails on the plugin version, revert
> the bump to 4.3.15 first.

### Register the Android SHA-1 (this is what breaks Google sign-in)

`mobile/android/app/google-services.json` currently has:

```json
"oauth_client": []
```

An empty `oauth_client` array means **no OAuth client exists for this Android
app**, and Google sign-in on Android fails with
`PlatformException(sign_in_failed, 10:)` no matter what the app code does.
Enabling the Google provider in the console is necessary but *not* sufficient:
that array is populated only once the app's signing-certificate fingerprint is
registered and the file is re-downloaded.

This does not affect web (`flutter run -d chrome`), which uses Firebase's
`signInWithPopup` and needs no OAuth client in `google-services.json` -- so
Chrome is the quickest way to test Google sign-in today.

1. Get the debug SHA-1 (the keystore is created by your first Android build, so
   run `flutter run` once if the file doesn't exist yet):

   ```bash
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
   ```

   On Windows the keystore lives at `%USERPROFILE%\.android\debug.keystore`.
   Copy the `SHA1:` line. For a release build, run the same command against your
   release keystore and register that fingerprint too.

2. Firebase console → **Project settings → Your apps → Android app
   (`com.example.safeher_app`) → Add fingerprint**, paste the SHA-1, save.

3. **Re-download `google-services.json`** and replace
   `mobile/android/app/google-services.json`. Confirm `oauth_client` is no longer
   empty — that is the check that tells you it worked.

4. Rebuild (`flutter clean && flutter run`). A Gradle-cached
   `google-services.json` will otherwise keep the old, empty one.

### iOS

Configured as of 2026-08-15. `mobile/ios/Runner/GoogleService-Info.plist` is in
place for project `safeher-2a1f2`, bundle id `com.example.safeherApp` — which
matches both `firebase_options.dart` and `PRODUCT_BUNDLE_IDENTIFIER` in the Xcode
project. Unlike the Android file, it carries a real `CLIENT_ID` and
`REVERSED_CLIENT_ID`, so an iOS OAuth client exists and Google sign-in does not
need a separate fingerprint registration.

Two wiring steps were done alongside it, both easy to miss:

1. **The plist is referenced from `Runner.xcodeproj/project.pbxproj`.** Dropping
   the file into `ios/Runner/` is not sufficient — Xcode only copies files listed
   in the target's Resources build phase. Without that entry the app builds fine
   and then fails at runtime with a missing-configuration error that reads like a
   code bug.
2. **`REVERSED_CLIENT_ID` is registered as a URL scheme in `Info.plist`.**
   `google_sign_in` completes its OAuth callback by opening that scheme; without
   it, sign-in hangs after the consent screen.

> **Unverified on device.** These changes were made on Windows, where Flutter
> cannot build for iOS. The plist and `Info.plist` were validated as parseable
> and the `project.pbxproj` edit was structurally checked, but no iOS build has
> been run. Verify on a Mac with `flutter build ios --debug` before trusting it.
> If Xcode reports a corrupt project file, restore
> `Runner.xcodeproj/project.pbxproj` from git and add the plist by dragging it
> into the Runner group in Xcode with "Runner" ticked under target membership.

### Web (`flutter run -d chrome`)

Web takes a different Google path: `AuthRepositoryRemote` uses Firebase's own
`signInWithPopup` there, so the SHA-1 and `google-services.json` above are
irrelevant on web, and no `google-signin-client_id` meta tag is needed in
`web/index.html`. What web does need:

- **Google enabled** under Authentication → Sign-in method (same as mobile).
- **Authorized domains** must include the host you're serving from. Firebase
  includes `localhost` by default, which covers `flutter run -d chrome`.

The backend must also be running, since the app talks to
`http://127.0.0.1:5000/api/v1` by default:

```bash
python -m uvicorn fastapi_app.main:app --host 127.0.0.1 --port 5000
```

CORS is already open in development (`ENVIRONMENT=development` sets
`allow_origins=["*"]`), so the browser's preflight succeeds. A
`DioException [connection error] … XMLHttpRequest onError` in the Chrome console
means the backend isn't reachable — that error is what a refused TCP connection
looks like from the browser, not a CORS or auth problem.

### Phone OTP is optional by design

Phone verification needs the Phone provider enabled, a registered SHA-1, and SMS
quota (billing, past the free tier). If it can't start, **sign-up still succeeds** —
the account is created and the backend session provisioned, and the OTP screen says
so and offers "Continue to SafeHer" rather than waiting on a code that will never
arrive. Linking a phone credential is an enhancement, not a precondition.

## 5. Retrain a model (optional)

Only the glove's model trains inside this repository, because its output is
compiled into the firmware beside it:

```bash
python glove/ml/scripts/extract_glove_features.py
python glove/ml/scripts/train_glove_7class_xgboost_v5.py
python glove/ml/scripts/evaluate_v5.py          # the one that matters
```

`evaluate_v5.py` simulates the rule the app actually applies — two FALL windows
above threshold within five seconds — over held-out recordings, rather than
reporting a per-window accuracy that a mostly-NORMAL dataset would flatter.

The weapon, audio and expression models train outside this repository; their
datasets run to gigabytes. Only the shipped artifacts are committed, under
`mobile/assets/models/` and `ml_models/`, each with its measured result recorded
in `mobile/assets/models/README.md`.

## Development workflow

```bash
make help          # list convenience targets
make install        # pip install -r requirements.txt
make clean           # remove __pycache__, *.pyc, flutter build artifacts
make flutter-setup    # flutter pub get
make flutter-run       # flutter run
make flutter-build      # flutter build apk --release
```

Note: `make setup`, `make train`, and `make test` reference `scripts/setup.py`,
`scripts/train_all.py`, and `scripts/test_apis.py`, which don't currently exist in
`scripts/` (only `scripts/smoke_firebase_exchange.py` does) — those three targets will
fail until those scripts are added. Use the commands in this file directly instead.

## Testing

```bash
# Backend
pytest tests/                              # some files are stale, see PROJECT_STRUCTURE.md
pytest tests/test_fastapi_contracts.py     # the reliable one — runs in-process, no server needed

# Mobile
cd mobile
flutter analyze
flutter test
```

## Troubleshooting

- **"JWT_SECRET_KEY must be set" on startup** — you're running with
  `ENVIRONMENT=production` or `staging` and either didn't set `JWT_SECRET_KEY` or left
  it as `change-me`. Set a real secret, or run with `ENVIRONMENT=development` locally.
- **SQLite "database is locked" or schema errors** — `fastapi_app/db.py` has an
  auto-repair guard that backs up and recreates a stale-schema SQLite file; if you hit
  this in dev, it's usually safe to delete the local `safeher.db` and let migrations
  recreate it (`alembic upgrade head`).
- **`/api/v1/media/sign-upload` returns 400 "Cloudinary is not configured"** — set the
  three `CLOUDINARY_*` variables in `.env`.
- **Event processor "not reachable" warning on `python app.py` startup** — expected if
  you haven't started `deployment/docker/docker-compose.yml`'s event-processor
  container; the backend still starts, threat processing just won't have a live
  processor to call.
- **Mobile: blank white screen after `flutter run -d web-server`** — this is normal on
  first load. Flutter web (debug/dartdevc) compiles ~900 modules on first request,
  which can take 10–20 seconds before the first paint. It's not a hang.
- **`mobile-ci.yml` never triggers** — fixed as of the 2026-08-08 audit; it previously
  filtered on `SafeHer/mobile/**` paths that never matched (the repo root already *is*
  `SafeHer`), so it silently never ran. It now filters on `mobile/**`.
