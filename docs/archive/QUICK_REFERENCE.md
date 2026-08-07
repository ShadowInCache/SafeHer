# 🚀 SafeHer Quick Reference Guide

## Start Here

### 1️⃣ First Time Setup
```bash
# Activate virtual environment
.\.venv\Scripts\Activate.ps1

# Install dependencies
pip install -r requirements.txt

# View setup guide
python QUICKSTART.py
```

### 2️⃣ Start the Services
```bash
# Option A: Start everything (Docker + Flask)
python manage.py start-all

# Option B: Manual control
python manage.py start              # Start Docker containers
python manage.py start-gateway      # Start Flask API in new terminal

# Check status
python manage.py status
```

### 3️⃣ Test the System
```bash
# Run all integration tests
python -m pytest tests/ -v

# Quick health check
curl http://localhost:5000/health
```

---

## 📍 Where to Go for What

| Goal | Go To | File |
|------|-------|------|
| **Add REST API endpoint** | `src/core/api_gateway.py` | Line: 200-1000 |
| **Add WebSocket feature** | `src/core/websocket_manager.py` | Line: 50-150 |
| **Add database table** | `src/services/database/db_service.py` | Line: 100-300 |
| **Handle MQTT messages** | `src/services/mqtt/mqtt_service.py` | Line: 150-250 |
| **Add authentication** | `src/utils/auth.py` | Line: 1-200 |
| **Configure system** | `.env` | All lines |
| **Add ML model** | `src/models/{model_name}/` | Create new dir |
| **Fix deployment** | `deployment/docker/docker-compose.yml` | All lines |

---

## 🔌 API Endpoints Quick Reference

### Health & Status
```bash
GET /health                         # Gateway health
GET /api/v1/processor/status        # Event processor details
GET /status                         # Full system status
```

### Events & Real-Time
```bash
GET /api/v1/events                  # Real-time events from Redis
GET /api/v1/events?limit=50         # Last 50 events
POST /api/v1/events/clear           # Clear Redis cache
WS  /ws/alerts/{user_id}            # WebSocket: Real-time alerts
```

### Archive (Supabase)
```bash
GET /api/v1/archive                 # Retrieve archived events
GET /api/v1/archive?threat_level=high  # Filter by threat
POST /api/v1/archive/post           # Manually archive event
```

### Threat Processing
```bash
POST /api/v1/process-threat         # Process threat through ML
POST /process-weapon                # Legacy: Weapon detection
POST /process-motion                # Legacy: Motion detection
POST /process-voice                 # Legacy: Voice threat
```

### Emergency Contacts
```bash
GET /emergency-contacts             # Get user's contacts
POST /emergency-contacts            # Add new contact
PUT /emergency-contacts/{id}        # Update contact
DELETE /emergency-contacts/{id}     # Remove contact
```

---

## 🧪 Running Tests

```bash
# All tests
python -m pytest tests/ -v

# Single test file
python -m pytest tests/test_integration.py -v

# Specific test
python -m pytest tests/test_api_gateway.py::test_health -v

# With coverage
python -m pytest tests/ --cov=src --cov-report=html

# Watch mode (requires pytest-watch)
ptw tests/
```

---

## 🐳 Docker Commands

```bash
# Start services
cd deployment/docker
docker-compose up -d

# Check running containers
docker-compose ps

# View logs
docker-compose logs -f               # All services
docker-compose logs -f processor     # Event processor only

# Stop services
docker-compose down

# Rebuild without cache
docker-compose build --no-cache
docker-compose up -d
```

---

## 🔧 Troubleshooting

### Services Won't Start
```bash
# Check port conflicts
netstat -ano | findstr :5000
netstat -ano | findstr :6379
netstat -ano | findstr :1883

# Stop conflicting processes (if port 5000 in use)
taskkill /PID <PID> /F
```

### Docker Issues
```bash
# Clean up everything
docker-compose down -v
docker system prune -a

# Rebuild fresh
docker-compose build --no-cache
docker-compose up -d
```

### Connection Issues
```bash
# Test Redis
redis-cli ping

# Test MQTT
mosquitto_sub -h localhost -t "safeher/#"

# Test Supabase
curl "https://pmniolsrmzevknwmdkcd.supabase.co/rest/v1/events?limit=1" \
  -H "apikey: <KEY_FROM_.env>"
```

---

## 📁 File Tree (Essential Files Only)

```
SafeHer/
├── app.py ............................ Entry point
├── manage.py ......................... Service manager
├── requirements.txt .................. Dependencies
├── .env .............................. Config (SECRET)
│
├── src/
│   ├── core/
│   │   ├── api_gateway.py ........... REST API + WebSocket
│   │   ├── websocket_manager.py .... Real-time alerts
│   │   └── orchestrator.py ......... Service orchestration
│   │
│   ├── services/
│   │   ├── database/db_service.py .. Database layer
│   │   └── mqtt/mqtt_service.py .... MQTT client
│   │
│   └── utils/
│       ├── auth.py .................. Authentication
│       └── config.py ................ Configuration
│
├── deployment/docker/
│   ├── docker-compose.yml .......... Full stack
│   └── safeher_event_processor.py .. Event processor
│
└── tests/
    └── test_integration.py ......... Full system tests
```

---

## 🔐 Environment Variables (.env)

```ini
# Database
DATABASE_URL=sqlite:///safeher.db

# Supabase (Cloud Archive)
SUPABASE_URL=https://pmniolsrmzevknwmdkcd.supabase.co
SUPABASE_KEY=your-public-key
SUPABASE_SECRET=your-secret-key

# Services
REDIS_URL=redis://localhost:6379
MQTT_BROKER=localhost
MQTT_PORT=1883

# API
API_HOST=0.0.0.0
API_PORT=5000
DEBUG=False

# ML Models
WEAPON_MODEL_PATH=runs/detect/weapon_detection/weights/best.pt
MOTION_MODEL_PATH=motion_training_results.json
VOICE_MODEL_PATH=xgboost_motion_model.json
```

---

## ✅ Pre-Deployment Checklist

- [ ] All containers running: `docker-compose ps`
- [ ] API gateway responds: `curl http://localhost:5000/health`
- [ ] Redis connected: `redis-cli ping`
- [ ] Supabase credentials valid: Check `.env`
- [ ] All tests passing: `python -m pytest tests/ -v`
- [ ] No uncommitted changes: `git status`
- [ ] Environment is production: `DEBUG=False` in `.env`

---

## 📞 Getting Help

1. **Check logs**: `docker-compose logs -f` or `python app.py`
2. **Run audit**: `python audit_system.py`
3. **Read docs**: `docs/BACKEND_INTEGRATION.md`
4. **Check structure**: `PROJECT_STRUCTURE.md`

---

## 🎯 Common Tasks

### Add new REST endpoint
1. Open `src/core/api_gateway.py`
2. Add route handler:
```python
@app.route('/api/v1/my-endpoint', methods=['GET'])
def my_endpoint():
    return {'status': 'ok'}, 200
```
3. Test: `curl http://localhost:5000/api/v1/my-endpoint`

### Add database schema
1. Open `src/services/database/db_service.py`
2. Add dataclass:
```python
@dataclass
class MyModel:
    id: int
    name: str
```
3. Create table in `init_database()`

### Add MQTT subscriber
1. Open `src/services/mqtt/mqtt_service.py`
2. Register callback:
```python
mqtt_service.register_callback('safeher/devices/+/events', handle_event)
```

---

## 📊 Architecture at a Glance

```
Device (Hardware)
       ↓ MQTT
    Broker
       ↓
Event Processor (Docker)
   ├─→ ML Inference
   ├─→ Threat Classification  
   └─→ Supabase Archive (Cloud)
       ↓ REST
   Flask API Gateway
   ├─→ REST Endpoints
   └─→ WebSocket Alerts
       ↓
   Client (Mobile/Web)
```

---

**Last Updated**: March 29, 2026  
**Status**: ✅ Production Ready  
**Confidence**: 100%
