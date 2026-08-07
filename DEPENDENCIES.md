# Dependencies

`requirements.txt` (root) mixes three concerns in one flat file: the current FastAPI
backend, the archived `legacy_flask_gateway/`, and the `ml_training/` pipeline. Grouped
below by what actually needs each one.

## Backend (`fastapi_app/`) — needed to run the app

| Package | Why |
|---|---|
| `fastapi` | Web framework |
| `uvicorn[standard]` | ASGI server |
| `python-jose[cryptography]` | JWT signing/verification |
| `passlib[bcrypt]` | Password hashing (`pbkdf2_sha256` primary, `bcrypt` for legacy hashes) |
| `pydantic-settings` | Typed env-var config (`fastapi_app/config.py`) |
| `httpx` | Outbound HTTP to the external threat processor |
| `sqlalchemy` | Async ORM |
| `alembic` | Schema migrations |
| `aiosqlite` | SQLite async driver (dev) |
| `asyncpg` | Postgres async driver (prod) |
| `asyncio-mqtt` | Device telemetry ingestion (`fastapi_app/mqtt_service.py`) |
| `cloudinary` | Signed direct-upload URLs for incident evidence |
| `supabase` | Events-archive client |
| `google-auth` | Verifies Firebase ID tokens for `/auth/firebase/exchange` |
| `python-dotenv` | Loads `.env` in `app.py` |
| `requests` | Sync HTTP, used for the startup dependency-reachability check |
| `redis[hiredis]` | Reachability check + shared with the event-processing pipeline |

`requirements.txt` previously listed `alembic` and bare `redis` twice each — deduped
as part of this audit (harmless either way since pip dedupes, but cleaner).

## Legacy (`legacy_flask_gateway/`) — only needed if you run the archived gateway

| Package | Why |
|---|---|
| `flask` | The old app framework |
| `flask-cors` | CORS for the old gateway |
| `flask-sock` | WebSocket support for the old gateway |
| `paho-mqtt` | MQTT client used by `legacy_flask_gateway/services/mqtt/` |

Not required for anything in `fastapi_app/` or `mobile/`. If `legacy_flask_gateway/`
is ever deleted outright (see the recommendation in the audit report), these four can
go with it.

## ML training (`ml_training/`) — only needed to retrain models

| Package | Why |
|---|---|
| `numpy`, `pandas`, `scipy` | Data handling |
| `scikit-learn`, `joblib` | Classical ML + model serialization |
| `xgboost` | Motion-detection model |
| `torch`, `torchvision`, `torchaudio` | Weapon-detection model backbone |
| `ultralytics` | YOLO-based weapon detection |
| `opencv-python`, `Pillow` | Image preprocessing |
| `librosa`, `soundfile` | Voice-distress audio feature extraction |

None of these are imported by `fastapi_app/` or `legacy_flask_gateway/` — they're a
training-time-only dependency set. If you're only running the backend, you can skip
installing this group (edit a local copy of `requirements.txt`, or split it into
`requirements-backend.txt` / `requirements-ml.txt` — see Recommendations in the audit
report).

**Note:** `opencv-python` showed no direct `import cv2` hit in a repo-wide grep during
this audit. Before removing it, check `ml_training/weapon_detection/` more closely — it's
plausible it's a transitive need of `ultralytics`, but this wasn't independently confirmed.

## Deployment-only (`deployment/docker/requirements.simple.txt`)

A separate, smaller requirements file for the Docker event-processor container —
not audited in depth here; check it directly if modifying `deployment/docker/`.

## Mobile (`mobile/pubspec.yaml`)

| Package | Why |
|---|---|
| `flutter_riverpod`, `riverpod_annotation` (+`riverpod_generator`, dev) | State management — the only allowed pattern per this project's build rules |
| `go_router` | Navigation — the only allowed pattern |
| `get_it`, `injectable` | DI, mainly for wiring Hive boxes |
| `dio` | HTTP client |
| `mqtt_client`, `web_socket_channel` | Realtime device/alert data |
| `hive_flutter`, `flutter_secure_storage` | Local persistence (session state, offline queue) |
| `firebase_core`, `firebase_auth`, `firebase_messaging`, `cloud_firestore` | Firebase integration |
| `flutter_animate`, `rive`, `lottie`, `animations` | Motion design system |
| `model_viewer_plus` | 3D device model rendering — added outside the original locked dependency list, on explicit request, for the device-management screen's 3D visual. Currently points at Google's public sample `.glb` models as placeholders (`SaSampleModels`) until real SafeHer-branded models exist |
| `google_fonts` | Inter + JetBrains Mono (design system typography) |
| `google_maps_flutter`, `geolocator` | Location sharing |
| `camera`, `record`, `chewie` | Evidence capture / playback |
| `fl_chart` | Dashboard data visualization |
| `flutter_blue_plus` | BLE device pairing |
| `intl` | Formatting |
| `freezed_annotation`, `json_annotation` (+`freezed`, `json_serializable`, dev) | Immutable models + serialization |
| `connectivity_plus` | Offline-queue connectivity awareness |
| `golden_toolkit`, `mockito` (dev) | Golden/screenshot tests, mocks |
| `webview_flutter_platform_interface` (dev) | Test double for `model_viewer_plus`'s WebView dependency in `flutter test` |

No unused mobile dependencies were identified — every package above has a
corresponding import in `mobile/lib/`.

## Alternatives considered (for future reference, not acted on)

- **Flask → FastAPI**: already done; this is why `legacy_flask_gateway/` exists.
- **`paho-mqtt` vs `asyncio-mqtt`**: the codebase currently has both (one per backend
  generation). Standardizing on `asyncio-mqtt` (already used by `fastapi_app/`) once
  `legacy_flask_gateway/` is fully retired would remove the duplication.
- **Splitting `requirements.txt`**: recommended — see DEPENDENCIES notes above and the
  Recommendations section of the audit report.
