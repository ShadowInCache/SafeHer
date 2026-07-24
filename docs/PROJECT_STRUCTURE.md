# SafeHer Project Structure - Optimized

## 📋 Overview

```
SafeHer/
├── app.py                          # ⭐ Entry point - Start here
├── manage.py                       # 🎮 CLI manager (start/stop/restart services)
├── QUICKSTART.py                   # 📖 Interactive setup guide
├── audit_system.py                 # 🔍 System audit tool
├── validate_dataset.py             # ✅ Dataset validation utility
├── requirements.txt                # 📦 Python dependencies
├── .env                            # ⚙️  Configuration (DO NOT COMMIT)
│
├── src/                            # 🏗️  Main application code
│   ├── __init__.py                 # Package init
│   ├── core/                       # 🧠 Core business logic
│   │   ├── __init__.py
│   │   ├── api_gateway.py          # ⭐ Flask REST API + WebSocket (20+ endpoints)
│   │   ├── websocket_manager.py    # 🔌 Real-time alert connections
│   │   └── orchestrator.py         # 🎼 Service orchestration
│   │
│   ├── services/                   # 🔧 Service layer
│   │   ├── __init__.py
│   │   ├── database/               # 💾 Data persistence
│   │   │   ├── __init__.py
│   │   │   └── db_service.py       # SQLite + Supabase integration
│   │   │
│   │   └── mqtt/                   # 📡 Device communication
│   │       ├── __init__.py
│   │       └── mqtt_service.py     # MQTT broker client
│   │
│   ├── utils/                      # 🛠️  Utilities
│   │   ├── __init__.py
│   │   ├── auth.py                 # Authentication & JWT
│   │   ├── config.py               # Configuration management
│   │   ├── validators.py           # Input validation
│   │   ├── logger.py               # Logging setup
│   │   └── user_manager.py         # User account management
│   │
│   └── models/                     # 🤖 ML Models
│       ├── __init__.py
│       ├── weapon_detection/       # 🔫 Threat detection
│       │   ├── __init__.py
│       │   └── train_weapon_model.py
│       │
│       ├── motion_detection/       # 👥 Anomaly detection
│       │   ├── __init__.py
│       │   └── train_motion_model.py
│       │
│       ├── voice_detection/        # 🔊 Audio threat detection
│       │   ├── __init__.py
│       │   └── train_voice_model.py
│       │
│       └── utils/                  # ML utilities
│           ├── __init__.py
│           └── gpu_utils.py        # GPU acceleration helpers
│
├── cloud_functions/                # ☁️  Serverless functions
│   ├── weapon_detection/main.py    # Threat detection endpoint
│   ├── motion_detection/main.py    # Motion analysis endpoint
│   ├── voice_analysis/main.py      # Voice threat endpoint
│   ├── threat_fusion/main.py       # Multi-model fusion logic
│   └── deploy.sh                   # Cloud deployment script
│
├── deployment/                     # 🚀 Deployment configurations
│   ├── docker/
│   │   ├── Dockerfile.processor    # Event processor container
│   │   ├── docker-compose.yml      # ⭐ 3-service orchestration (Redis, MQTT, Processor)
│   │   ├── safeher_event_processor.py  # Event processing + Supabase archival
│   │   └── event_system/           # Docker-only services
│   │       ├── __init__.py
│   │       ├── processor.py        # Event pipeline
│   │       └── ml_inference.py     # ML model inference
│   │
│   ├── config/
│   │   ├── mosquitto.conf          # MQTT broker config
│   │   ├── nginx.conf              # Reverse proxy config
│   │   ├── prometheus.yml          # Monitoring config
│   │   ├── redis.conf              # Redis persistence config
│   │   └── ssl/                    # SSL certificates
│   │
│   └── scripts/
│       └── start_all_services.ps1  # PowerShell startup script
│
├── tests/                          # ✅ Test suite
│   ├── __init__.py
│   ├── test_integration.py         # Full system integration tests
│   ├── test_api_gateway.py         # REST API endpoint tests
│   ├── test_microservices.py       # Service layer tests
│   └── test_authentication.py      # Auth mechanism tests
│
├── datasets/                       # 📊 ML Training data
│   ├── weapon_detection/
│   │   ├── data.yaml               # YOLO format config
│   │   ├── images/ (train/, val/)
│   │   └── labels/ (train/, val/)
│   │
│   ├── motion_detection/
│   │   ├── processed/
│   │   └── raw/
│   │
│   └── voice_detection/
│       ├── audio/
│       └── spectrograms/
│
├── runs/                           # 📈 Training/detection outputs
│   └── detect/
│       ├── weapon_detection/
│       ├── weapon_detection2/
│       ├── weapon_detection3/
│       └── weapon_detection4/
│
├── mobile/                         # 📱 Flutter mobile app
│   ├── lib/
│   │   ├── main.dart              # App entry
│   │   ├── core/                  # Business logic
│   │   ├── data/                  # Data layer
│   │   ├── presentation/          # UI screens
│   │   └── services/              # API clients
│   │
│   ├── test/
│   ├── pubspec.yaml               # Flutter dependencies
│   └── assets/                    # Images, fonts, sounds
│
├── docs/                          # 📚 Documentation
│   ├── COMPREHENSIVE_PROJECT_REPORT.md
│   ├── PROJECT_STATUS.md
│   ├── TECHNICAL_INVENTORY.md
│   └── BACKEND_INTEGRATION.md     # API & integration guide
│
├── hardware/                      # 🔧 Embedded code
│   ├── esp32_cam/
│   │   └── smart_glasses.ino      # Video capture + processing
│   │
│   └── esp32_glove/
│       └── smart_glove.ino        # Gesture + motion sensors
│
├── LICENSE
├── Makefile                       # Build automation
└── README.md                      # Quick start guide
```

---

## 🎯 Quick Start

```bash
# 1. Navigate to project
cd SafeHer

# 2. Start all services (Docker + Flask)
python manage.py start-all

# 3. Run integration tests
python -m pytest tests/ -v

# 4. Access APIs
curl http://localhost:5000/health              # Gateway health
curl http://localhost:5000/api/v1/events       # Real-time events
wscat -c ws://localhost:5000/ws/alerts/user1   # WebSocket alerts
```

---

## 🗂️ Directory Purposes

| Directory | Purpose | Status |
|-----------|---------|--------|
| `src/` | Core application code | ✅ Active |
| `src/core/` | API gateway, WebSocket, orchestration | ✅ Production |
| `src/services/` | Database, MQTT, external integrations | ✅ Production |
| `src/utils/` | Auth, config, logging, validation | ✅ Production |
| `src/models/` | ML training scripts | ✅ Active |
| `deployment/` | Docker, nginx, MQTT, Redis configs | ✅ Production |
| `cloud_functions/` | Serverless inference endpoints | ✅ Deployed |
| `tests/` | Integration & unit tests | ✅ Active |
| `datasets/` | ML training datasets | 📦 Data files |
| `runs/` | Model training outputs | 📈 Outputs |
| `mobile/` | Flutter iOS/Android app | 📱 In development |
| `hardware/` | ESP32 firmware | 🔧 Deployed |
| `docs/` | Guides & API documentation | 📚 Reference |

---

## ⭐ Key Application Files

### Entry Points
- **`app.py`** - Start Flask API gateway
  ```bash
  python app.py
  ```

- **`manage.py`** - Manage services (Docker + Flask)
  ```bash
  python manage.py start              # Start Docker containers
  python manage.py start-gateway      # Start Flask API
  python manage.py status             # Check service health
  ```

### Core Logic
- **`src/core/api_gateway.py`** - REST API & WebSocket endpoints
  - 20+ endpoints for events, archival, processing
  - WebSocket for real-time threat alerts
  - Health checks for all services

- **`src/services/database/db_service.py`** - Multi-backend storage
  - SQLite for local persistence
  - Supabase for cloud archival
  - Emergency contacts, incidents, devices

- **`src/services/mqtt/mqtt_service.py`** - Device communication
  - MQTT pub/sub for device events
  - Automatic reconnection with exponential backoff
  - Topic-based message routing

### Deployment
- **`deployment/docker/docker-compose.yml`** - Full stack orchestration
  - Redis 7 (cache + persistence)
  - MQTT broker (device communication)
  - Event processor (ML + Supabase integration)

- **`deployment/docker/safeher_event_processor.py`** - Main event handler
  - Redis event consumption
  - ML threat detection
  - Supabase archival via REST API

---

## 📦 Dependencies

All dependencies managed in `requirements.txt`:
```
Flask==3.0.0              # Web framework
Flask-CORS==4.0.0         # Cross-origin requests
Flask-Sock==0.2.0         # WebSocket support
redis==5.0.1              # Cache & queue
paho-mqtt==1.6.1          # Device communication
supabase==2.0.2           # Cloud database
requests==2.31.0          # HTTP client
sqlalchemy==2.0.0         # ORM
python-dotenv==1.0.0      # Environment config
numpy==1.24.0             # Scientific computing
opencv-python==4.8.0      # Computer vision
torch==2.0.0              # Deep learning
xgboost==2.0.0            # Gradient boosting
```

---

## 🧪 Testing

```bash
# Run all tests
python -m pytest tests/ -v

# Run specific test suite
python -m pytest tests/test_integration.py -v
python -m pytest tests/test_api_gateway.py -v
python -m pytest tests/test_authentication.py -v

# Run with coverage
python -m pytest tests/ --cov=src --cov-report=html
```

---

## 🚀 Deployment

### Docker (Production)
```bash
cd deployment/docker
docker-compose up -d
```

### Flask API (Development)
```bash
python app.py
# Runs on http://localhost:5000
```

### Cloud Functions (Serverless)
```bash
cd cloud_functions/weapon_detection
./deploy.sh
```

---

## 🔧 Configuration

Edit `.env` for:
- Database URLs (SQLite/PostgreSQL)
- Supabase credentials
- MQTT broker address
- Redis connection
- ML model paths
- API ports

---

## 📊 Service Architecture

```
┌─────────────────────────────────────────┐
│          Mobile App (Flutter)            │
│        HTTP + WebSocket Clients          │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│    Flask API Gateway (Port 5000)         │
│  • REST Endpoints (20+)                  │
│  • WebSocket Manager                     │
│  • Request Validation                    │
└──────────────┬──────────────────────────┘
               │
    ┌──────────┼──────────┐
    │          │          │
┌───▼──┐ ┌─────▼───┐ ┌───▼──────┐
│Redis │ │   MQTT  │ │Database  │
│Cache │ │ Broker  │ │ Service  │
└───┬──┘ └────┬────┘ └───┬──────┘
    │         │          │
    │    ┌────▼──────┐   │
    │    │  Event    │   │
    │    │Processor  │   │
    │    └───┬────┬──┘   │
    │        │    │      │
    │    ┌───▼─┐ ┌▼──┐   │
    │    │ ML  │ │AWS│   │
    │    │Infr.│ │Lambda  │
    │    └─────┘ └─────┘  │
    │                     │
    └────────┬────────────┘
             │
    ┌────────▼──────────────┐
    │  Supabase  PostgreSQL │
    │   Cloud Archive       │
    │   (REST API)          │
    └───────────────────────┘
```

---

## ✅ Verification

Run the audit tool to verify everything:
```bash
python audit_system.py
```

Expected output:
```
✅ 18-20 tests passing
⚠️  0-1 expected warnings
❌ 0 critical errors
```

---

## 📝 File Statistics

- **Total Python Files**: 44
- **Core Application**: 12 (app + services + utils)
- **ML Models**: 7 (training + inference)
- **Tests**: 4
- **Deployment**: 5
- **Cloud Functions**: 4
- **Configuration**: 5

---

## 🎓 Learning Path

1. **Start**: `app.py` - Understand entry point
2. **Read**: `src/core/api_gateway.py` - Learn endpoints
3. **Explore**: `src/services/` - Understand integrations
4. **Deploy**: `deployment/docker/docker-compose.yml` - Run full stack
5. **Test**: `tests/test_integration.py` - Verify connectivity
6. **Extend**: Add new endpoints to `api_gateway.py`

---

Generated: 2026-03-29
Status: ✅ Optimized & Clean
