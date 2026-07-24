#!/usr/bin/env python3
"""
SafeHer Quick Start Guide
Get the complete backend system running in minutes
"""

import sys

def main():
    print("""
╔═══════════════════════════════════════════════════════════════════════╗
║                   🛡️  SAFEHER QUICK START GUIDE                       ║
║              Complete Backend Integration - 4 Simple Steps            ║
╚═══════════════════════════════════════════════════════════════════════╝

📋 PREREQUISITES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Docker & Docker Compose installed
✅ Python 3.8+ installed
✅ Supabase account with API keys configured in .env
✅ All services Docker images built (done automatically)


🚀 STEP 1: INSTALL PYTHON DEPENDENCIES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    cd SafeHer/
    pip install -r requirements.txt

⏱️ Expected time: 2-5 minutes


🐳 STEP 2: START DOCKER SERVICES (Terminal 1)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    python manage.py start

This will start:
  🔵 Redis         (Port 6379)  - Real-time event storage
  🔵 MQTT Broker   (Port 1883)  - Device communication
  🔵 Event Processor (Port 8080) - ML inference and threat detection

Expected output:
    ✅ Docker services started successfully
    ✅ Event Processor: Running
    ✅ Redis: Ready
    ✅ MQTT: Ready

⏱️ Expected time: 30-45 seconds


🌐 STEP 3: START API GATEWAY (Terminal 2)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    cd SafeHer/
    python manage.py start-gateway

This will start:
  ✨ Flask API Gateway (Port 5000)
  📡 WebSocket Server for real-time alerts
  🔌 REST API endpoints

Expected output:
    🚀 Starting Flask server on port 5000...
    Running on http://0.0.0.0:5000

⏱️ Expected time: 5-10 seconds


✅ STEP 4: VERIFY INSTALLATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Option A: Run integration tests (Terminal 3)
    python test_integration.py

Option B: Check service status
    python manage.py status

Option C: Test manually with curl
    curl http://localhost:5000/health
    curl http://localhost:5000/api/v1/archive?limit=5


🎯 EXPECTED RESULTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Event Processor Health:
    curl http://localhost:8080/health
    
    Response:
    {
      "status": "healthy",
      "redis": "connected",
      "mqtt": "disconnected",  ← OK (timing)
      "supabase": "connected"
    }

✅ API Gateway Health:
    curl http://localhost:5000/health
    
    Response:
    {
      "status": "healthy",
      "services": { ... }
    }

✅ Supabase Connection:
    curl 'http://localhost:5000/api/v1/archive?limit=5'
    
    Response:
    {
      "archived_events": [...],
      "total": 0,
      "source": "supabase_rest_api"
    }


📚 KEY ENDPOINTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

HEALTH & STATUS
  GET /health                    - Quick health check
  GET /status                    - Detailed system status
  GET /api/v1/processor/status   - Event processor details

EVENT PROCESSING
  POST /api/v1/process-threat    - Submit threat data for ML analysis

REAL-TIME EVENTS
  GET /api/v1/events             - Get recent events from Redis
  GET /api/v1/archive            - Get archived events from Supabase
  POST /api/v1/archive/post      - Manually archive an event

SHIFT MANAGEMENT
  GET /api/v1/shifts/{user_id}/events  - Get shift-specific events

REAL-TIME ALERTS
  WS /ws/alerts/{user_id}        - WebSocket connection for alerts

EMERGENCY CONTACTS
  GET  /api/v1/emergency-contacts/{user_id}
  POST /api/v1/emergency-contacts
  PUT  /api/v1/emergency-contacts/{contact_id}
  DELETE /api/v1/emergency-contacts/{contact_id}


🎮 USAGE EXAMPLES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Check System Status
    python manage.py status

2. View Processor Logs
    python manage.py logs processor

3. Test Threat Processing
    curl -X POST http://localhost:5000/api/v1/process-threat \\
      -H "Content-Type: application/json" \\
      -d '{
        "device_id": "cam_1",
        "user_id": "user_123",
        "type": "image",
        "data": {"image": "base64_encoded..."}
      }'

4. Get Archived Events
    curl 'http://localhost:5000/api/v1/archive?limit=100&threat_level=high'

5. Get Shift Events
    curl 'http://localhost:5000/api/v1/shifts/user_123/events?start_time=2026-03-29T08:00:00Z&end_time=2026-03-29T16:00:00Z'

6. Connect to Real-time Alerts (JavaScript)
    const ws = new WebSocket('ws://localhost:5000/ws/alerts/user_123');
    ws.onmessage = (e) => console.log('Alert:', JSON.parse(e.data));


📖 DOCUMENTATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Detailed documentation available:
  📄 docs/BACKEND_INTEGRATION.md     - Complete integration guide
  📄 docs/COMPREHENSIVE_PROJECT_REPORT.md - Full project overview
  📄 docs/TECHNICAL_INVENTORY.md     - Technical specifications


🔧 TROUBLESHOOTING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Problem: Docker images missing
Solution:
    cd deployment/docker
    docker-compose build --no-cache

Problem: Port already in use
Solution:
    lsof -i :5000    # Check what's using port 5000
    kill -9 <PID>    # Kill the process
    
    Or change port in .env:
    FLASK_PORT=8000

Problem: Supabase connection failed
Solution:
    1. Check .env file has correct keys
    2. Verify Supabase project is active
    3. Check table 'events' exists in Supabase
    
    Create table with:
    python setup_supabase_table.py

Problem: Gateway can't reach Event Processor
Solution:
    1. Check processor is running: docker-compose ps
    2. Test connectivity: curl http://localhost:8080/health
    3. Verify docker network: docker network ls


🎯 WHAT'S RUNNING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Environment:
  ✅ Docker Containers:
     - safeher_redis (Redis 7)
     - safeher_mqtt (Eclipse Mosquitto)
     - safeher_event_processor (Custom Event Processor)
  
  ✅ Python Services:
     - Flask API Gateway
     - WebSocket Manager
     - Database Service (SQLite)
  
  ✅ Cloud Services:
     - Supabase PostgreSQL
     - Supabase REST API
     - Supabase Storage

Network Topology:
  Mobile/Web Apps
         ↓
  API Gateway (5000)
         ↓
  Event Processor (8080)
         ↓
  Redis (6379) + MQTT (1883) + Supabase


📊 STORAGE ARCHITECTURE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Real-time Events:    Redis (in-memory, fast, ~30 min retention)
Persistent Logs:     SQLite (local database)
Evidence Archive:    Supabase PostgreSQL (cloud, secure, queryable)
ML Model Data:       File storage (dataset files)
Device Messages:     MQTT Broker (pub/sub, no persistence)


🎓 NEXT STEPS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Deploy ML models and train if needed
2. Configure emergency contacts and procedures
3. Set up mobile app to connect to gateway
4. Configure MQTT topics for your devices
5. Test end-to-end threat detection workflow
6. Deploy to production infrastructure


💡 TIPS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

• Keep separate terminals open for Docker logs and Gateway
• Use 'python manage.py logs processor' to debug issues
• Test with Postman, curl, or your mobile app
• Enable debug logging in .env: FLASK_ENV=development
• Monitor Supabase dashboard for archived events

═══════════════════════════════════════════════════════════════════════

Ready to go! Your SafeHer backend is fully integrated and operational. 🚀

Questions? Check: docs/BACKEND_INTEGRATION.md
    """)

if __name__ == '__main__':
    main()
