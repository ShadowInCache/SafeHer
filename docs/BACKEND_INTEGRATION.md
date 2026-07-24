# SafeHer Backend Integration Guide

## Overview

This document describes the complete integration of all SafeHer services including:
- **Docker Services**: Redis, MQTT, Event Processor
- **API Gateway**: Flask-based REST and WebSocket server
- **Storage**: Redis (real-time), SQLite (local), Supabase (cloud archive)
- **Real-time Communication**: WebSocket alerts and pub/sub

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Mobile/Web Apps                           │
└───────────────────────┬──────────────────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────────────┐
        │   API Gateway (Flask)              │
        │   Port: 5000                       │
        │   - REST Endpoints                 │
        │   - WebSocket Alerts               │
        │   - Request Routing                │
        └───┬──────────────────────────┬────┘
            │                          │
            ▼                          ▼
    ┌──────────────────┐      ┌──────────────────────┐
    │ Event Processor  │      │  Database Service    │
    │ (Docker)         │      │  - SQLite (local)    │
    │ Port: 8080       │      │  - Supabase (cloud)  │
    │ - ML Models      │      │  - Contacts          │
    │ - Threat Detect  │      │  - Shift Events      │
    └────┬─────────────┘      └──────────────────────┘
         │
    ┌────┴─────────────────────┬─────────────────────┐
    │                          │                     │
    ▼                          ▼                     ▼
┌─────────┐            ┌──────────────┐      ┌──────────────────┐
│ Redis   │            │ MQTT Broker  │      │ Supabase Cloud   │
│ 6379    │            │ 1883         │      │ events table     │
│ Real-   │            │ Device       │      │ evidence archive │
│ time    │            │ messaging    │      │ REST API         │
└─────────┘            └──────────────┘      └──────────────────┘
```

## Service Components

### 1. API Gateway (Flask)
**Port**: 5000  
**File**: `src/core/api_gateway.py` / `app.py`

**Key Responsibilities:**
- REST API endpoints for mobile/web clients
- WebSocket server for real-time alerts
- Request authentication and routing
- Database service proxying
- Health monitoring

**Main Endpoints:**
```
GET  /health                              # Health check
GET  /status                              # Service status
GET  /api/v1/archive                      # Get archived events
POST /api/v1/archive/post                 # Manual event archiving
GET  /api/v1/events                       # Real-time events (Redis)
GET  /api/v1/shifts/{user_id}/events     # Shift-specific events
POST /api/v1/alerts/broadcast             # Broadcast alerts
GET  /ws/alerts/{user_id}                 # WebSocket connection
```

### 2. Event Processor (Docker)
**Port**: 8080  
**Docker Image**: `docker-safeher_processor`  
**File**: `deployment/docker/safeher_event_processor.py`

**Key Responsibilities:**
- Event processing and threat detection
- ML model inference
- MQTT message handling
- Redis caching
- Supabase REST API integration

**Main Endpoints:**
```
GET  /health                              # Health check
GET  /api/events                          # Redis stored events
GET  /api/archive                         # Supabase archived events
POST /api/archive/post                    # Archive to Supabase
POST /api/process                         # Process event
GET  /api/status                          # Detailed status
```

### 3. Redis
**Port**: 6379  
**Container**: `safeher_redis`  
**Image**: `redis:7-alpine`

**Usage:**
- Real-time event storage
- Message queue
- Session cache
- WebSocket message queue

### 4. MQTT Broker
**Port**: 1883 (MQTT) / 9001 (WebSocket)  
**Container**: `safeher_mqtt`  
**Image**: `eclipse-mosquitto:2.0`

**Topics:**
```
safeher/devices/{device_id}/events        # Raw sensor data
safeher/devices/{device_id}/status        # Device heartbeats
safeher/alerts/{user_id}                  # User-specific alerts
safeher/emergency                         # Emergency broadcast
```

### 5. Supabase Cloud Database
**URL**: `https://pmniolsrmzevknwmdkcd.supabase.co`  
**Table**: `events`

**Purpose:**
- Long-term evidence archival
- Audit trail
- Queryable threat history
- Cloud backup

## Installation & Setup

### Prerequisites
- Docker & Docker Compose
- Python 3.8+
- Supabase account with API keys

### Step 1: Clone and Install
```bash
cd SafeHer
pip install -r requirements.txt
```

### Step 2: Configure Environment
Create or update `.env` file:
```env
# Flask Configuration
FLASK_ENV=development
FLASK_PORT=5000

# Docker Services
EVENT_PROCESSOR_URL=http://localhost:8080
REDIS_HOST=localhost
REDIS_PORT=6379
MQTT_HOST=localhost
MQTT_PORT=1883

# Supabase Configuration
SUPABASE_URL=https://pmniolsrmzevknwmdkcd.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_EV3r8bTigsvSyGyqDl_Mvw_H9I32zv7
SUPABASE_SECRET_KEY=sb_secret_Z8KIkef56gyYNBmzzjPAEg_an9RpQhO

# Database
DATABASE_URL=sqlite:///safeher.db
```

### Step 3: Initialize Supabase Table
```bash
# The SQL file is already prepared
# Just run it in Supabase SQL Editor once:
# supabase_setup.sql
```

### Step 4: Start Services
```bash
# Start Docker services (Redis, MQTT, Event Processor)
python manage.py start

# Start API Gateway in another terminal
python manage.py start-gateway

# Or start everything together
python manage.py start-all
```

## Usage Examples

### 1. Check Service Status
```bash
python manage.py status
```

Output:
```
Docker Compose Status:
  safeher_redis              ✅ Healthy
  safeher_mqtt               ✅ Healthy
  safeher_event_processor    ✅ Healthy

API Gateway:           ✅ Running
Event Processor:       ✅ Running
```

### 2. Process a Threat Event
```bash
curl -X POST http://localhost:5000/api/v1/process-threat \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "camera_1",
    "user_id": "user_123",
    "type": "image",
    "data": {
      "image_base64": "...",
      "timestamp": "2026-03-29T20:00:00Z"
    },
    "location": {"lat": 40.7128, "lng": -74.0060}
  }'
```

### 3. Retrieve Archived Events
```bash
# Get last 100 events
curl 'http://localhost:5000/api/v1/archive?limit=100'

# Get high-threat events
curl 'http://localhost:5000/api/v1/archive?limit=50&threat_level=high'

# Get events by type
curl 'http://localhost:5000/api/v1/archive?limit=100&event_type=weapon'
```

### 4. Get Shift Events
```bash
curl 'http://localhost:5000/api/v1/shifts/user_123/events?start_time=2026-03-29T08:00:00Z&end_time=2026-03-29T16:00:00Z'
```

### 5. Connect to Real-time Alerts (WebSocket)
```javascript
const ws = new WebSocket('ws://localhost:5000/ws/alerts/user_123');

ws.onopen = (event) => {
  console.log('Connected to alerts');
  // Send heartbeat
  ws.send(JSON.stringify({ type: 'ping' }));
};

ws.onmessage = (event) => {
  const alert = JSON.parse(event.data);
  console.log('Threat alert:', alert);
};

ws.onerror = (error) => {
  console.error('WebSocket error:', error);
};
```

### 6. Manually Archive an Event
```bash
curl -X POST http://localhost:5000/api/v1/archive/post \
  -H "Content-Type: application/json" \
  -d '{
    "type": "manual_threat",
    "threat_level": "high",
    "topic": "test/manual",
    "user_id": "user_123",
    "device_id": "device_456"
  }'
```

## API Endpoint Reference

### Health & Status Endpoints

#### GET /health
Returns basic health status.

**Response:**
```json
{
  "status": "healthy",
  "redis": "connected",
  "mqtt": "disconnected",
  "supabase": "connected"
}
```

#### GET /status
Returns detailed system status.

**Response:**
```json
{
  "status": "running",
  "service": "safeher-api-gateway",
  "version": "1.0.0",
  "timestamp": "2026-03-29T20:00:00Z"
}
```

### Event Processing Endpoints

#### POST /api/v1/process-threat
Process threat data through unified ML pipeline.

**Request:**
```json
{
  "device_id": "camera_1",
  "user_id": "user_123",
  "type": "image|motion|audio|panic",
  "data": {...},
  "location": {"lat": 0.0, "lng": 0.0}
}
```

**Response:**
```json
{
  "threat_detected": true,
  "confidence": 0.95,
  "threat_level": "high",
  "event_type": "weapon",
  "processing_time_ms": 250
}
```

### Archive Endpoints

#### GET /api/v1/archive
Retrieve archived events from Supabase.

**Query Parameters:**
- `limit` (int): Max events to return (default: 100, max: 1000)
- `threat_level` (str): Filter by threat level
- `event_type` (str): Filter by event type
- `user_id` (str): Filter by user ID

**Response:**
```json
{
  "status": "success",
  "archived_events": [...],
  "total": 45,
  "source": "supabase_rest_api"
}
```

#### POST /api/v1/archive/post
Manually archive an event.

**Request:**
```json
{
  "type": "string",
  "threat_level": "low|medium|high|critical",
  "topic": "string",
  "user_id": "string"
}
```

#### GET /api/v1/events
Get real-time events from Redis.

**Query Parameters:**
- `limit` (int): Max events (default: 50)

**Response:**
```json
{
  "events": [...],
  "total": 10,
  "source": "redis_real_time"
}
```

#### GET /api/v1/shifts/{user_id}/events
Get events for a specific shift/time period.

**Query Parameters:**
- `start_time` (ISO datetime): Required
- `end_time` (ISO datetime): Required
- `threat_level` (str): Optional filter

**Response:**
```json
{
  "user_id": "user_123",
  "shift_window": {
    "start_time": "2026-03-29T08:00:00Z",
    "end_time": "2026-03-29T16:00:00Z"
  },
  "events": [...],
  "total": 15
}
```

### WebSocket Endpoints

#### GET /ws/alerts/{user_id}
WebSocket connection for real-time threat alerts.

**Connection:**
```
ws://localhost:5000/ws/alerts/user_123
```

**Message Types:**

Heartbeat:
```json
{"type": "ping"}
```

Response:
```json
{"type": "pong", "timestamp": "2026-03-29T20:00:00Z"}
```

Alert:
```json
{
  "type": "threat_alert",
  "alert_id": "alert_1234567890",
  "severity": "high",
  "message": "Threat detected with 95% confidence",
  "confidence": 0.95,
  "timestamp": "2026-03-29T20:00:00Z"
}
```

### Emergency Contacts Endpoints

#### GET /api/v1/emergency-contacts/{user_id}
Get all emergency contacts for a user.

**Response:**
```json
{
  "status": "success",
  "contacts": [...],
  "count": 3
}
```

#### POST /api/v1/emergency-contacts
Add a new emergency contact.

**Request:**
```json
{
  "user_id": "user_123",
  "name": "John Doe",
  "phone_number": "555-1234",
  "email": "john@example.com",
  "relationship": "family",
  "priority": 1
}
```

## Troubleshooting

### Event Processor Not Running
```bash
# Check logs
python manage.py logs processor

# Rebuild and restart
python manage.py restart
```

### Redis Connection Failed
```bash
# Check Redis is running
docker ps | grep redis

# Or check manually
redis-cli ping
# Should return: PONG
```

### Supabase Connection Issues
```bash
# Verify REST API connectivity
curl -H "Authorization: Bearer YOUR_SECRET_KEY" \
  https://pmniolsrmzevknwmdkcd.supabase.co/rest/v1/

# Should return 200 or 401 (auth error)
```

### WebSocket Not Connecting
```bash
# Check gateway is running on port 5000
curl http://localhost:5000/health

# Test WebSocket with wscat
npm install -g wscat
wscat -c 'ws://localhost:5000/ws/alerts/test_user'
```

## Development

### Running Tests
```bash
python -m pytest tests/ -v
```

### Adding New Endpoints
1. Add route in `src/core/api_gateway.py`
2. Define request/response schema
3. Add unit tests in `tests/`
4. Update API documentation

## Monitoring & Logs

### View Docker Logs
```bash
# All services
python manage.py logs

# Specific service
python manage.py logs processor
python manage.py logs mqtt
python manage.py logs redis
```

### View Flask Gateway Logs
```bash
# Started with manage.py start-gateway
# Logs appear in terminal
```

## Performance Considerations

- **Redis**: In-memory storage for real-time events (configurable retention)
- **SQLite**: Local database for persistent storage
- **Supabase**: Cloud database for long-term archive
- **MQTT**: Pub/sub for device communication (no persistence by default)

## Security Notes

⚠️ **Important**: The current Supabase RLS policy allows all operations. Before production:

1. Update RLS policy to restrict access
2. Add user authentication to API Gateway
3. Enable HTTPS/WSS
4. Rotate API keys regularly
5. Add request rate limiting
6. Implement API key rotation

## Future Enhancements

- [ ] Kubernetes deployment
- [ ] gRPC support for high-performance ML inference
- [ ] Event streaming with Apache Kafka
- [ ] Advanced analytics dashboard
- [ ] Mobile push notifications
- [ ] ML model versioning and A/B testing
- [ ] Automated threat response integration
- [ ] Multi-region redundancy
