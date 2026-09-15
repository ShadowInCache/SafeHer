# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning
follows [Semantic Versioning](https://semver.org/). This project has not cut a formal
release yet — entries below are grouped by notable milestones instead of version tags
until the first tagged release.

## [Unreleased]

### 2026-09-16 — 5-class glove model, and a review of what it left inconsistent

#### Changed
- **Glove model is now 5-class (PR #32, `e15b70b`).** `PUSH`/`PULL`/`JERK`
  merged into `SUDDEN_MOVEMENT`; 3,000 trees, 37,176 nodes. Locked-test accuracy
  0.8886, macro F1 0.9001 — but missed-fall windows rose from 8 to 12.
  Shipped in `SafeHer_Glove_V5_OnDevice/`, with `SUDDEN_MOVEMENT` debounced over
  two windows on the glove.
- App label set, threat mapping and `motion_data.dart` updated to five classes.
- `scripts/check_glove.py` knows the five labels, reads both firmware payloads,
  and says which sketch is flashed.

#### Fixed
- **Glove gave no readings.** `SafeHer_Glove_V5_OnDevice.ino` was committed with
  `DATA_COLLECTION_MODE 1`, which never starts BLE. Back to `0`.
- **Each app parser read only one firmware payload.** Against `V5_OnDevice` the
  Motion Risk card showed `--`; against `SafeHer_Glove_Final` the alarm path read
  the label as `CLASS=FALL` and could never fire. `GloveClassification.tryParse`
  and `parseMotionPacket` now both accept `FALL,0.93` and
  `CLASS=FALL,CONFIDENCE=0.9300`.
- **Closing the pairing sheet could stop auto-SOS readings.** The alarm path and
  the Motion Risk card each subscribed to the classification characteristic, and
  whichever cancelled first switched notifications off for both.
  `FlutterBluePlusBleService` now shares one subscription and switches off only
  when the last listener leaves. It also uses `onValueReceived` rather than
  `lastValueStream`, which replayed the previous connection's reading as new.
- **Tests that passed without testing anything.** Four test files still used
  `PUSH`/`PULL`/`JERK`; two failed, and two passed only because unknown labels
  also never trigger. Rewritten for `SUDDEN_MOVEMENT`, with new tests pinning
  both payload formats.

#### Still open
- `SafeHer_Glove_Final`, both diagnostics and Failure Capture still carry the
  7-class model.
- The shared subscription is untested against a real radio — the tests use a
  fake BLE service.

### 2026-09-11 — glove ML integration merged, and the wearables meet real hardware

#### Added
- **Glove ML integration (PR #30).** Finalised on-device glove pipeline and
  firmware (`glove/firmware/SafeHer_Glove_Final/`), a motion risk score with BLE
  offline detection and auto-reconnect, and a batch of new labelled recordings
  (fall/jerk/normal). Merged into `main` at `0fb6075`.
- **First real ESP32-C3 hardware validation of the glove** (2026-09-10,
  `HARDWARE_VALIDATION_REPORT.md`): MPU-6500 detected, 100 Hz sampling with
  sub-11µs jitter, on-device 7-class inference at ~31 ms/window with sampling
  never starved. Plus two new diagnostic sketches (hardware-only, inference) and
  a failure-capture sketch.
- **Weapon detector wired into the app.** `ultralytics_weapon_detector.dart`
  scores frames on-device on Android, `remote_weapon_detector.dart` uploads a
  sampled frame to the server on web, `weapon_scorer.dart` votes over a window,
  and `mjpeg_client.dart` parses the glasses stream. This closes the
  2026-09-01 "nothing loads the model" gap.
- **Glasses camera path**: streaming firmware (`SafeHer_Glasses_Stream`), pairing
  that refuses anything not identifying as `safeher-glasses`, and an mDNS resolver
  so `safeher-glasses.local` resolves on Android (where `.local` otherwise fails)
  while the release cleartext policy stays keyed on the hostname (`f401821`).

#### Changed
- **Audio distress signal replaced.** The CNN+LSTM keyword spotter (below,
  2026-09-01) was dropped — it spotted `stop`/`no`/`off`/`down`, not real
  phrases, and scored below a fuzzy string match on real speech. Replaced by a
  pure-Dart TF-IDF + logistic-regression phrase classifier
  (`threat_phrase_classifier.dart` + `phrase_classifier.json`, ~196 kB, web-safe)
  over the platform speech recogniser. Measured on synthetic/degraded TTS;
  recording a real distress corpus is deferred (no public dataset supplies it).

#### Two build settings the hardware run surfaced
The inference firmware overflows the default flash partition (needs **Huge APP
3MB No OTA**), and **USB CDC On Boot** must be **Enabled** or `Serial` is silent
on the ESP32-C3. Both are board-menu settings, not code changes.

#### Where the three signals stand
- **glove** — trained, connected, firmware hardware-validated; app pairing +
  motion/FALL/BLE still unverified
- **weapon** — trained (mAP@0.5 0.907), wired on-device (Android) and via server
  fallback (web); no real glasses stream yet
- **audio** — pure-Dart classifier wired; validated on synthetic TTS, not real
  distress

889 mobile tests, 483 backend (7 skipped), analyzer clean.


### 2026-09-01 — the third signal, and the scorer that decides what a detection means

#### Added
- **CNN+LSTM audio keyword spotter.** Google Speech Commands v0.02, canonical
  split. **98.9% test accuracy**, `stop` at 99.3% recall / 99.0% precision,
  every target word above 93% on both. INT8 at **1.12 MB**, lossless.
- **`WeaponScorer`** — turns per-frame detections into `weapon_score` using a
  vote over the last five frames rather than the best single frame. `0.84,
  0.88, 0.86` is a weapon; `0.42, 0.08, 0.03` is a reflection and scores as
  one. Frames expire, so a detection from before the camera cut out cannot
  combine with one after it. 11 tests.

#### Fixed
- **`_silence_` was a class with zero samples** — declared in the label space
  and absent from the data, because torchaudio's loader yields only spoken
  words. It scored 0.0% recall on 0 support. Now built from the corpus's
  `_background_noise_`, reaching 100% recall. This matters for deployment more
  than for the metric: a keyword spotter that has only ever heard speech will
  confidently hear a word in traffic noise.
- **The silence generator re-decoded minute-long WAVs hundreds of times**,
  exhausting virtual memory on a 3.7 MiB allocation and starving the GPU to 7%
  utilisation. Each source is now read once and sliced; GPU went to 97%.

#### Not done, deliberately
The `onnxruntime` Flutter package was **not** added. It has no web support
("coming soon") and web is a declared target; it was last published two years
ago by an unverified uploader. Taking an unmaintained native dependency that
breaks one of two platforms, for a code path with no camera or microphone feed,
is not correct wiring. The scoring rules are built and tested; running the
models stays a seam, as `BleService` and `SafetyForegroundService` already are.

#### Where the three signals stand
- **glove** — trained, connected, raising alarms
- **weapon** — trained (mAP@0.5 0.907), scorer built and tested, no frame source
- **audio** — trained (98.9%), no scorer yet, no microphone feed

Emotion is trained too (65.5%) and stays supporting evidence: its `fear` class
runs at 47% recall, which is the argument for keeping it out of the score.

758 mobile tests, 468 backend, analyzer clean. APK 76.3 → 77.2 MB.


### 2026-09-01 — a facial-expression classifier, and why it stays out of the score

#### Added
- **Facial expression classifier.** MobileNetV3-Small over FER2013's canonical
  split, **65.5% test accuracy**, exported to fp16 at 3.09 MB and bundled at
  `mobile/assets/models/emotion_mobilenetv3_fp16.onnx`. Two-stage by design: a
  face detector crops, this classifies the crop. Training "fear face" as a YOLO
  class would have asked one nano backbone to do localisation and fine-grained
  classification at once, and spent weapon-detection capacity doing it.

#### The finding worth reading
`fear` — the only class with any safety relevance — is the model's **weakest**:
47.0% recall, 56.1% precision. It misses more than half of fearful faces and is
right barely more often than a coin toss when it fires. That is not a defect
more epochs would fix; it is what facial expression recognition is like, and it
is the strongest practical argument for the architecture already in place:
expression goes to `SupportingContext` and cannot reach `ThreatSignals`.

65.5% overall is also not underperformance. Human agreement on FER2013 is about
65%. Anything much above 75% on this dataset should be read as a leak.

#### Fixed before it shipped
- **INT8 quantisation destroys this model** — 65.5% to **16.9%**, barely above
  the 14.3% random baseline; per-channel is no better at 18.7%. MobileNetV3's
  hard-swish and squeeze-excite blocks over depthwise separable convolutions
  have per-channel weight ranges that per-tensor scaling collapses.
  Caught only by validating on the real test set: a random-input check reported
  **100% agreement** between INT8 and fp32, because noise produces garbage
  logits that agree by luck. The broken INT8 files were deleted rather than
  left in `exported/`. fp16 is lossless here and half the size.
- A first FER2013 mirror (`3una/Fer2013`) turned out to hold **700 images, 100
  per class** — a toy subset. Training on it would have produced a confident,
  meaningless number. Switched to `AutumnQiu/fer2013`, which has the real
  28,709 / 3,589 / 3,589 split.

#### Still true
Nothing loads either model. No ONNX runtime dependency, no inference code.
APK 73.7 → 76.3 MB.


### 2026-09-01 — the weapon detector, and the knife gap it opened

#### Added
- **A trained weapon detector.** YOLOv8n, pistol and knife, trained on an
  RTX 3050 from 7,539 images assembled out of Open Images V7,
  OD-WeaponDetection and Sohas. Held-out test split: **mAP@0.5 0.907,
  mAP@0.5:0.95 0.652, recall 0.835**; pistol AP 0.930, knife AP 0.884.
  Quantised to INT8 at **3.36 MB** and bundled at `mobile/assets/models/`.
- `docs/WEAPON_INFERENCE_PLACEMENT.md` — why the model runs on the phone and
  not the glasses, with the arithmetic. An ESP32-CAM has 520 KB of SRAM and
  4 MB of PSRAM against 3.36 MB of weights, a 1.23 MB input tensor and tens of
  megabytes of activation memory, on a chip with no neural accelerator facing
  8.1 GFLOPs a frame. Two orders of magnitude, not a tuning problem.

#### Fixed
- **Knife detection was materially worse than pistol** — AP@0.5 0.859 against
  0.929, recall 0.763 against 0.830. The diagnosis ruled out the obvious cause:
  knife recall was *flat across box sizes* and worse than pistol even on large
  boxes, which is the signature of intra-class variance rather than
  resolution. Root cause: Open Images treats `Knife`, `Kitchen knife` and
  `Dagger` as three separate boxable classes and the first download asked only
  for `Knife`. Adding the other two lifted knife training boxes 26% and took
  **knife recall from 0.763 to 0.827**, closing the pistol/knife recall gap
  from 6.7 points to 1.6.

#### Changed
- Docs corrected throughout: the project no longer has "no trained detection
  model". It has two — the glove, which is connected, and the weapon detector,
  which is not. `README.md`, `SRS_STATUS.md`, `TRACEABILITY.md` and
  `ARCHITECTURE.md` now distinguish those two states rather than collapsing
  them.
- Counts: 468 backend tests (was 409), APK 71.5 -> 73.7 MB, web build added to
  the verified gates.

#### Still true
Nothing loads the model. No ONNX runtime dependency, no inference code,
`weapon_score` has no producer, and `DetectionSources` does not claim one. A
model in the assets folder and a working detector are different things.

468 backend + 747 mobile tests passing, analyzer clean, APK and web both build.


### 2026-08-30 — three signals decide the threat score, and nothing else

#### Changed
- **The fusion engine takes exactly three primary signals** — glove (XGBoost),
  weapon (YOLOv8), audio (CNN+LSTM) — and SRS §6.2's additive context boosters
  are gone from the score. Night, high-risk zone and heart rate were context,
  not evidence that an assault is happening, and the weapon booster
  double-counted a detection already entering through the vision weight. All of
  it is still recorded, via a new `SupportingContext`, for the incident and the
  summary. **Scores at night and in high-risk zones are lower than before** —
  the intended consequence, recorded as a deviation in `SRS_STATUS.md`.
- **The weights invert §6.2** to 0.40 weapon / 0.35 audio / 0.25 glove, ordered
  by how ambiguous each signal is. This costs the glove nothing today: it is
  the only reporting signal, and `fuse()` renormalises over whatever reported.

#### Fixed
- **A knife detected at 0.90 confidence scored SAFE.** Under §6.2's weights the
  least ambiguous signal in the system carried the least weight, and two quiet
  sensors averaged a confident weapon detection down to 0.28. Found by the new
  acceptance matrix, not by reading the code. Fixed by the re-weighting above
  plus a solo-signal floor: the score never falls below half the strongest
  single reading, because a knife in view is not made safe by a calm wrist.

#### Added
- `ThreatSignals` (three fields, frozen) and `SupportingContext` (everything
  else), so the separation is enforced by construction rather than by comment.
  `tests/test_fusion_architecture.py` fails if the shape changes, if the
  weights and fields drift apart, or if `evaluate()` grows a contextual
  parameter.
- A threat state machine — SAFE / ELEVATED / HIGH / CRITICAL — with hysteresis,
  so a score resting on a band boundary does not flap every heartbeat.
- Corroboration: independent signals agreeing score above their weighted mean,
  capped so agreement alone can never raise an alarm.
- The architecture's own acceptance matrix as tests, including the two that
  matter most: fear on a face and rapidly changing GPS both leave the score
  untouched.

468 backend tests passing (was 436), 7 skipped, no regressions.


### 2026-08-30 — the two recorded findings, resolved; iOS out, web in

#### Fixed
- **The access token no longer travels in a URL.** `WS /ws/alerts/{user_id}`
  took `?token=<access jwt>`, putting a 15-minute credential into every proxy
  and access log between the client and the app. A browser handshake cannot
  carry an `Authorization` header, so moving it to one was never an option —
  especially now that web is a target. Instead `POST /ws/ticket` is
  authenticated normally, where the token stays in a header, and returns a
  ~30-second ticket that opens the alert feed and nothing else. A ticket
  recovered from a log is long dead. `WS_ALLOW_LEGACY_TOKEN_QUERY` re-enables
  the old handshake for already-installed builds and **defaults to false**;
  the compatibility path still enforces ownership.
- **Roles are server-assigned.** `POST /auth/firebase/exchange` accepted a
  `role` in the body and applied it at provisioning. It was allow-listed and
  granted nothing today, because `require_roles` is used by no route — which
  was exactly the danger: the first route gated on `guardian` would have
  turned a sign-up field into privilege escalation, and whoever wrote it
  would have had no reason to suspect. The field is gone; accounts provision
  as `user`.

#### Changed
- **Web is a supported target; iOS is out of scope.** `flutter build web
  --release` compiles clean and is now part of the release checks. A web build
  has no glove — `flutter_blue_plus` has no web implementation, so BLE and
  everything downstream of it are absent there — and `FlutterSecureStorage`
  falls back to browser storage rather than a Keychain, which is a weaker
  guarantee than the Android Keystore. Both are documented rather than papered
  over. The `dart:io` guard test, written before web was a target, is why
  enabling one needed no porting.

#### Added
- `TestTicketsReplaceTokensInTheUrl` and `TestLegacyTokenHandshakeIsOptIn` —
  the access token no longer opens the feed, a ticket is refused as a bearer
  token, minting requires a caller, an expired ticket fails, and the
  compatibility path works when enabled while still checking ownership.

436 backend tests passing (was 428), 747 mobile, analyzer clean, Android APK
71.5 MB and web both building.


### 2026-08-30 — security audit: one real hole, and two boundaries nobody was watching

#### Fixed
- **Unthrottled outbound email to an arbitrary address.**
  `POST /users/me/emergency-contacts/{id}/verify/send` sends a code to an
  address the caller chose and had no rate limit, while every other
  mail-sending route had one — the action sits past a path parameter and no
  prefix rule reached it. An account could add any address as a "contact" and
  loop the endpoint to bomb that inbox from SafeHer's verified sender. Capped
  at 12/hour. `RateLimitRule` gained an optional `suffix` so a rule can target
  an action past a path parameter without throttling its neighbours.
- **A provider exception was returned to the caller.** The same route answered
  `Could not send the code: {exc}`, handing the upstream error body — and
  whatever hostnames or configuration detail it carried — to any authenticated
  client. Logged server-side now, with a generic message to the user. It was
  the only instance of that pattern in the codebase.

#### Added
- `tests/test_realtime_and_device_isolation.py` — cross-account tests for the
  two id-bearing routes that had none: the live alert WebSocket
  (`WS /ws/alerts/{user_id}`, which had no test anywhere) and
  `POST /devices/{id}/heartbeat`. Both were already correctly guarded; neither
  was proven. The WebSocket tests speak the ASGI protocol directly, because
  Starlette's `TestClient` is incompatible with the installed httpx.
- `TestRouteRegistry` — every id-bearing route must be classified as
  owner-checked or token-credential, and the suite fails when a new one
  appears unclassified or an entry goes stale. The two gaps above existed
  because nothing noticed them; this makes the absence itself fail.
- `tests/test_outbound_email_abuse.py` — pins the new limit and, as
  importantly, pins that it did not spread to reading or editing contacts.

#### Verified, not changed
Authorization was audited across all 22 id-bearing routes and found correct
everywhere: ownership is re-derived from the token, and missing and not-yours
both return 404. Tokens are held in `FlutterSecureStorage`, not Hive. Evidence
is AES-256-GCM sealed before any backend sees a byte, retrieval is
ownership-checked and streamed, and no public URL is ever issued. Uploads are
MIME allow-listed and size-capped. The unhandled-exception handler returns a
generic 500. No secrets are tracked in the repository.

428 backend tests passing (was 409), 7 skipped, no regressions.


### 2026-08-29 — the glove detects with the phone in a pocket

#### Added
- **Background detection.** `mobile/lib/core/background/safety_foreground_service.dart`
  runs a `connectedDevice|location` foreground service (via
  `flutter_foreground_task`) for exactly as long as a glove is connected, so
  Android stops freezing the process and the BLE notifications keep arriving.
- `GloveAutoTrigger` (`mobile/lib/features/safety/data/glove_auto_trigger.dart`)
  — the glove's vote, moved out of a widget and into a `keepAlive` provider.
- `DetectionSources.backgroundWatchActive` — reports whether the service is
  *genuinely* running, so the UI only claims the pocket case works when the
  platform confirms it started.
- A background alarm path: the countdown is routed to first and the screen
  woken second, so it is already up when the activity comes forward.
- 34 tests, including the glove vote driven entirely without a widget tree, and
  the BLE wire contract asserted against the firmware's literal payloads.
- `glove/README.md` and a rewritten `mobile/README.md`.

#### Fixed
- **Automatic detection was silently conditional on the app being looked at.**
  The glove's vote ran inside `SafetyTriggerListener.build()`, and Flutter stops
  pumping frames when the app leaves the screen — so a pocketed phone, the case
  the glove exists for, raised nothing. A foreground service alone would not
  have fixed this: the process would have been alive with nothing reading the
  stream.
- **The device card claimed a heart rate of zero.** The firmware sends `0` for
  bpm and battery to avoid fabricating sensor data, but a literal `0` parses as
  a measurement. Both now read as absent — no wearer has a heart rate of zero,
  and no glove transmitting over BLE has a flat battery. `accelG` and `gyroDps`
  keep zero as a real reading.
- `ref.read` during provider disposal threw; the service handle is resolved in
  `build` and held.
- `dart:io` in a web-reachable library broke the web build, caught by the repo's
  own guard test. Replaced with `defaultTargetPlatform`.

#### Changed
- Android manifest gains `FOREGROUND_SERVICE_CONNECTED_DEVICE` and the
  `<service>` declaration. Release APK 70.7 MB → 71.5 MB.
- Documentation rewritten against current source: `README.md`,
  `docs/PROJECT_STRUCTURE.md`, `docs/ARCHITECTURE.md`, `docs/TRACEABILITY.md`,
  `docs/SRS_STATUS.md`. Test counts were three sessions stale (639 → 747 mobile,
  342 → 409 backend) and `glove/` was absent from every structural document.


### 2026-08-15 — Firebase auth, design system, repo cleanup

#### Added
- iOS Firebase configuration: `GoogleService-Info.plist`, referenced from the
  Xcode Resources build phase, with `REVERSED_CLIENT_ID` registered as a URL
  scheme for `google_sign_in`. Not verified by an iOS build (Windows host).
- Guest sign-in (Firebase Anonymous) — "Continue as guest" reaches the SOS button
  without an account. The backend still provisions a real account keyed to the
  Firebase uid.
- `AuthRepositoryNative` — email/password auth served directly by `fastapi_app`,
  selectable with `--dart-define=USE_FIREBASE_AUTH=false`. Needs no Firebase console
  configuration.
- SRS section 4.1 auth: emailed OTP verification (FR-AUTH-01), password change with
  cross-device session revocation (FR-AUTH-06), 5-failure/15-minute lockout
  (FR-AUTH-07), 30-day deletion grace with an hourly purge worker (FR-AUTH-08),
  and password reset by OTP.
- `SaAmbientBackground` — a global aurora layer giving the glassmorphism in SRS
  section 1 something to refract.
- 51 new tests: `test_auth_security.py` (27), `test_firebase_token_verification.py`
  (8), `auth_repository_native_test.dart` (16).

#### Fixed
- **Alembic could never run.** `alembic/env.py` drove an async URL with a sync
  engine (`MissingGreenlet`), and `alembic/script.py.mako` was missing so no
  migration could be generated. The dev database had been built by `create_all`
  with no `alembic_version` row and six unapplied migrations.
- **Firebase tokens rejected on clock skew.** A machine a second behind Google saw
  fresh tokens fail as "Token used too early" — intermittent, unreproducible
  sign-in failures. Now tolerates 30s.
- **Response headers were silently dropped.** The global `HTTPException` handler
  discarded `exc.headers`, killing `Retry-After` on lockouts and
  `WWW-Authenticate` on 401s across every endpoint.
- Phone and anonymous accounts were all filed under `@phone.safeherapp.com`; the
  synthetic address is now provider-aware.
- Token lifetimes corrected to 15 minutes / 30 days per FR-AUTH-04 (were 30 min / 7 days).
- Light mode: login and forgot-password forced a dark background and used hardcoded
  white text, failing the 4.5:1 contrast floor in SRS 5.4. Shadows were neutral
  black where SRS section 2.4 specifies violet.

#### Changed
- Android: `com.google.gms.google-services` 4.3.15 → 4.5.0; removed the
  `com.google.firebase.crashlytics` Gradle plugin, which was applied without
  `firebase_crashlytics` ever being in pubspec.yaml.

#### Removed
- `legacy_flask_gateway/` — the superseded Flask backend. Nothing outside itself
  imported it. `flask`, `flask-cors` and `paho-mqtt` were **kept** because
  `deployment/docker/safeher_event_processor.py` imports them; `flask-sock` was
  dropped as genuinely unused.
- `mobile/deprecated/legacy_flutter_tree/` (134 files) — an older Flutter tree,
  unreferenced by `mobile/lib` or `mobile/test`.
- `mobile/.chrome_fresh_profile/` (3,152 files, ~400 MB) — a committed Chrome
  profile. The 2026-08-08 entry below claims this was untracked, but `git ls-files`
  still listed every file, so that cleanup never actually landed.
- `tests/test_microservices.py` (8/8 skipped; targets ports 8001-8004 that no longer
  exist) and `tests/test_authentication.py` (undefined `token` fixture).
- Empty root `lib/` and `test/` directory skeletons; all tracked `__pycache__` and
  `*.db` files (`safeher.db` and `test_safeher.db` kept on disk as live dev data).
- Working tree: 389 MB → 103 MB.


### Added
- Full documentation set: `README.md`, `ARCHITECTURE.md`, `API.md`, `SETUP.md`,
  `CONTRIBUTING.md`, `DEPENDENCIES.md`, `PROJECT_STRUCTURE.md`, `SECURITY.md`,
  `MEMORY.md` (this file's companion).
- `docs/archive/` — every pre-audit doc preserved for historical reference.

### Changed
- Renamed `src/models/` → `ml_training/` and `src/` (remaining Flask gateway code) →
  `legacy_flask_gateway/` for clarity; updated the two files with hardcoded `src/...`
  paths (`cloud_functions/voice_analysis/main.py`, `validate_dataset.py`) and the two
  internal absolute imports in the relocated gateway code.
- Fixed `.github/workflows/mobile-ci.yml`: its path filters and working directory
  referenced `SafeHer/mobile/**`, which never matched real paths in this repo (the
  repo root already is `SafeHer`) — the workflow had never actually triggered.
  Corrected to `mobile/**`, and broadened `flutter analyze lib/main.dart lib/app` (a
  nonexistent path) to a plain `flutter analyze`.

### Removed
- `audit_system.py` — dead script auditing the (now-archived) legacy Flask gateway,
  referenced by nothing else in the repo.
- `hardware/esp32_cam/smart_glasses.ino` — byte-identical duplicate of
  `glasses/firmware/legacy_esp32cam/smart_glasses.ino`.
- `deployment/docker/dy` — a stray cached HTTP error response, not source code.

### Fixed / Security
- Removed `deployment/docker/.env` (containing live Supabase keys) from git tracking.
  **The key must still be rotated manually** — it was present on `origin/main` since
  the repo's first commit and must be treated as compromised regardless of the
  untrack. See [SECURITY.md](SECURITY.md).
- Untracked `mobile/.chrome_fresh_profile/` (an accidentally-committed Chrome browser
  <!-- NOTE 2026-08-15: this untracking never landed; the files were still in the
  index and were removed for real on 2026-08-15. -->
  profile, ~3,150 files), all `__pycache__/` directories, and the four root-level
  `.db` files (`safeher.db`, `safeher.runtime.db`, `safeher_app.db`,
  `test_safeher.db`) — none of these should be version-controlled. `.gitignore`
  expanded to prevent recurrence.

## Prior history (untagged)

Reconstructed from commit history and the archived reports in `docs/archive/` for
context — not exhaustive:

- **2026-04-19** — Real API integration layer, offline queue (Hive-backed retry +
  connectivity awareness), accessibility/performance audit pass on `mobile/`.
- **2026-04-03** — FastAPI backend (`fastapi_app/`) introduced alongside the existing
  Flask gateway; `app.py` becomes the primary backend entrypoint.
- **2026-03-23 to 2026-03-30** — Original Flask-based event-processor architecture,
  ML training pipeline (motion/voice/weapon detection), ESP32 firmware, Docker Compose
  deployment, and the first project audit reports (now in `docs/archive/`).
- **2026-02-08** — Repository initialized, MIT license added.

## [0.1.0] — baseline

The state of the project immediately before the 2026-08-08 audit: a working FastAPI
backend, an in-progress Flutter mobile app (mock-backed, Phases 0–6 of its own build
sequence complete through Home + offline queue + accessibility audit), ESP32 firmware
for two devices, four ML inference cloud functions, and a Docker Compose deployment —
alongside an unused legacy Flask backend and several git-hygiene issues addressed in
[Unreleased](#unreleased) above.
