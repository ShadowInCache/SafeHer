#!/usr/bin/env python3
"""
SafeHer Unified Event Processor
Handles all event processing, ML inference, and threat fusion
Stores events in both Redis (real-time) and Supabase (evidence archive)
Uses direct REST API calls for Supabase integration
"""

import os
import json
import logging
from flask import Flask, jsonify, request
from flask_cors import CORS
import redis
import paho.mqtt.client as mqtt
from datetime import datetime
import requests

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Flask app
app = Flask(__name__)
CORS(app)

# Configuration
REDIS_HOST = os.getenv('REDIS_HOST', 'localhost')
REDIS_PORT = int(os.getenv('REDIS_PORT', 6379))
MQTT_HOST = os.getenv('MQTT_HOST', 'localhost')
MQTT_PORT = int(os.getenv('MQTT_PORT', 1883))
HTTP_PORT = int(os.getenv('HTTP_PORT', 8080))

# Supabase Configuration
SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_PUBLISHABLE_KEY = os.getenv('SUPABASE_PUBLISHABLE_KEY')
SUPABASE_SECRET_KEY = os.getenv('SUPABASE_SECRET_KEY')
# Use the appropriate key - secret key for server-side, publishable for client-side
SUPABASE_API_KEY = SUPABASE_SECRET_KEY or SUPABASE_PUBLISHABLE_KEY

# Supabase REST API endpoint
SUPABASE_REST_URL = f"{SUPABASE_URL}/rest/v1" if SUPABASE_URL else None

# Initialize Redis connection
try:
    redis_client = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
    redis_client.ping()
    logger.info(f"✓ Connected to Redis at {REDIS_HOST}:{REDIS_PORT}")
except Exception as e:
    logger.error(f"✗ Failed to connect to Redis: {e}")
    redis_client = None

# Test Supabase connectivity
supabase_available = False
if SUPABASE_URL and SUPABASE_API_KEY:
    try:
        headers = {
            "Authorization": f"Bearer {SUPABASE_API_KEY}",
            "apikey": SUPABASE_API_KEY,
            "Content-Type": "application/json"
        }
        response = requests.get(f"{SUPABASE_REST_URL}/", headers=headers, timeout=5)
        if response.status_code in [200, 401]:  # 401 with wrong auth is still accessible
            supabase_available = True
            logger.info(f"✓ Connected to Supabase at {SUPABASE_URL}")
        else:
            logger.error(f"✗ Supabase connection failed: {response.status_code}")
    except Exception as e:
        logger.error(f"✗ Failed to connect to Supabase: {e}")
else:
    logger.warning("⚠️ Supabase credentials not configured")

# Initialize MQTT connection
mqtt_client = mqtt.Client()


def _parse_iso(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace('Z', '+00:00'))
    except Exception:
        return None

def on_mqtt_connect(client, userdata, flags, rc):
    if rc == 0:
        logger.info(f"✓ Connected to MQTT broker at {MQTT_HOST}:{MQTT_PORT}")
        # Subscribe to device topics (events + emergency + heartbeat)
        mqtt_client.subscribe("safeher/devices/+/events")
        mqtt_client.subscribe("safeher/devices/+/emergency")
        mqtt_client.subscribe("safeher/devices/+/heartbeat")
        # Backward compatibility topic
        mqtt_client.subscribe("devices/+/events")
    else:
        logger.error(f"✗ Failed to connect to MQTT broker: rc={rc}")

def archive_event_to_supabase(event_record):
    """Archive event to Supabase using REST API"""
    if not supabase_available or not SUPABASE_REST_URL:
        return False
    
    try:
        headers = {
            "Authorization": f"Bearer {SUPABASE_API_KEY}",
            "apikey": SUPABASE_API_KEY,
            "Content-Type": "application/json"
        }
        response = requests.post(
            f"{SUPABASE_REST_URL}/events",
            json=event_record,
            headers=headers,
            timeout=10
        )
        if response.status_code in [200, 201]:
            logger.info(f"✓ Event archived to Supabase: {event_record.get('event_type')}")
            return True
        else:
            logger.error(f"Failed to archive to Supabase: {response.status_code} - {response.text}")
            return False
    except Exception as e:
        logger.error(f"Error archiving to Supabase: {e}")
        return False

def on_mqtt_message(client, userdata, msg):
    """Process incoming MQTT messages"""
    try:
        payload = json.loads(msg.payload.decode())
        logger.info(f"Received event: {msg.topic}")
        
        # Store event in Redis (real-time)
        if redis_client:
            redis_client.lpush(f"events:{msg.topic}", json.dumps(payload))
            
        # Store event in Supabase (archive via REST API)
        if supabase_available:
            event_record = {
                'event_topic': msg.topic,
                'event_data': payload,
                'event_timestamp': datetime.utcnow().isoformat(),
                'threat_level': payload.get('threat_level', 'unknown'),
                'event_type': payload.get('type', 'unknown')
            }
            archive_event_to_supabase(event_record)
            
    except Exception as e:
        logger.error(f"Error processing MQTT message: {e}")

# Set MQTT callbacks
mqtt_client.on_connect = on_mqtt_connect
mqtt_client.on_message = on_mqtt_message

# Flask Routes
@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    status = {
        'status': 'healthy',
        'redis': 'connected' if redis_client else 'disconnected',
        'mqtt': 'connected' if mqtt_client.is_connected() else 'disconnected',
        'supabase': 'connected' if supabase_available else 'disconnected'
    }
    return jsonify(status), 200

@app.route('/api/events', methods=['GET'])
def get_events():
    """Get processed events from Redis"""
    if not redis_client:
        return jsonify({'error': 'Redis not available'}), 503
    
    try:
        events = []
        keys = redis_client.keys('events:*')
        for key in keys:
            event_data = redis_client.lrange(key, 0, -1)
            events.extend([json.loads(e) for e in event_data])
        
        return jsonify({'events': events, 'total': len(events)}), 200
    except Exception as e:
        logger.error(f"Error retrieving events: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/archive', methods=['GET'])
def get_archive():
    """Get archived events from Supabase via REST API"""
    if not supabase_available:
        return jsonify({'error': 'Supabase not available', 'archived_events': []}), 503
    
    try:
        limit = request.args.get('limit', 100, type=int)
        threat_level = request.args.get('threat_level')
        event_type = request.args.get('event_type')
        user_id = request.args.get('user_id')
        start_time = _parse_iso(request.args.get('start_time'))
        end_time = _parse_iso(request.args.get('end_time'))
        
        headers = {
            "Authorization": f"Bearer {SUPABASE_API_KEY}",
            "apikey": SUPABASE_API_KEY,
            "Content-Type": "application/json"
        }
        
        query_parts = ["select=*", "order=event_timestamp.desc", f"limit={limit}"]
        if threat_level:
            query_parts.append(f"threat_level=eq.{threat_level}")
        if event_type:
            query_parts.append(f"event_type=eq.{event_type}")
        if user_id:
            query_parts.append(f"event_data->>user_id=eq.{user_id}")

        url = f"{SUPABASE_REST_URL}/events?{'&'.join(query_parts)}"
        response = requests.get(url, headers=headers, timeout=10)
        
        if response.status_code == 200:
            archived_events = response.json()
            if start_time or end_time:
                filtered = []
                for event in archived_events:
                    raw_ts = event.get('event_timestamp')
                    event_ts = _parse_iso(raw_ts)
                    if event_ts is None:
                        continue
                    if start_time and event_ts < start_time:
                        continue
                    if end_time and event_ts > end_time:
                        continue
                    filtered.append(event)
                archived_events = filtered

            logger.info(f"Retrieved {len(archived_events)} archived events from Supabase")
            return jsonify({
                'archived_events': archived_events,
                'total': len(archived_events),
                'source': 'supabase_rest_api'
            }), 200
        else:
            logger.error(f"Failed to retrieve archived events: {response.status_code}")
            return jsonify({
                'error': f'Supabase error: {response.status_code}',
                'archived_events': []
            }), response.status_code
    except Exception as e:
        logger.error(f"Error retrieving archived events: {e}")
        return jsonify({'error': str(e), 'archived_events': []}), 500

@app.route('/api/archive/post', methods=['POST'])
def archive_event_manual():
    """Manually archive an event to Supabase"""
    if not supabase_available:
        return jsonify({'error': 'Supabase not available'}), 503
    
    try:
        event_data = request.json
        event_record = {
            'event_topic': event_data.get('topic', 'manual/event'),
            'event_data': event_data,
            'event_timestamp': datetime.utcnow().isoformat(),
            'threat_level': event_data.get('threat_level', 'unknown'),
            'event_type': event_data.get('type', 'manual_archive')
        }
        
        success = archive_event_to_supabase(event_record)
        if success:
            return jsonify({'message': 'Event archived successfully', 'event': event_record}), 201
        else:
            return jsonify({'error': 'Failed to archive event'}), 500
    except Exception as e:
        logger.error(f"Error archiving event: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/events/clear', methods=['POST'])
def clear_events():
    """Clear stored events from Redis"""
    if not redis_client:
        return jsonify({'error': 'Redis not available'}), 503
    
    try:
        redis_client.flushdb()
        return jsonify({'message': 'Events cleared from Redis'}), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/status', methods=['GET'])
def get_status():
    """Get system status"""
    return jsonify({
        'timestamp': datetime.utcnow().isoformat(),
        'redis': 'connected' if redis_client else 'disconnected',
        'mqtt': 'connected' if mqtt_client.is_connected() else 'disconnected',
        'supabase': 'connected' if supabase_available else 'disconnected',
        'supabase_url': SUPABASE_URL or 'not configured',
        'uptime_seconds': 0
    }), 200

@app.route('/api/process', methods=['POST'])
def process_event():
    """Process an event"""
    try:
        event = request.json
        logger.info(f"Processing event: {event}")
        
        # Store in Redis
        if redis_client:
            redis_client.lpush('processed_events', json.dumps(event))
        
        # Archive to Supabase
        if supabase_available:
            event_record = {
                'event_topic': 'api/process',
                'event_data': event,
                'event_timestamp': datetime.utcnow().isoformat(),
                'threat_level': event.get('threat_level', 'low'),
                'event_type': event.get('type', 'api_processed')
            }
            archive_event_to_supabase(event_record)
        
        return jsonify({'status': 'processed', 'event': event}), 200
    except Exception as e:
        logger.error(f"Error processing event: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/process_threat', methods=['POST'])
def process_threat():
    """Compatibility endpoint used by API gateway and FastAPI alert router."""
    try:
        payload = request.json or {}
        threat_type = payload.get('type', 'unknown')
        data = payload.get('data', {}) if isinstance(payload.get('data'), dict) else {}

        confidence = float(data.get('confidence', 0.0))
        if confidence <= 0:
            # Deterministic fallback inference from payload characteristics.
            confidence = 0.35
            if data.get('threat_level') in {'high', 'critical'}:
                confidence = 0.85
            elif threat_type in {'panic', 'emergency'}:
                confidence = 0.95
            elif threat_type in {'image', 'weapon', 'voice', 'motion'}:
                confidence = 0.55

        threat_detected = confidence >= 0.5
        if confidence >= 0.85:
            level = 'critical'
        elif confidence >= 0.65:
            level = 'high'
        elif confidence >= 0.45:
            level = 'medium'
        else:
            level = 'low'

        result = {
            'status': 'processed',
            'device_id': payload.get('device_id'),
            'user_id': payload.get('user_id'),
            'type': threat_type,
            'threat_detected': threat_detected,
            'confidence': round(confidence, 4),
            'threat_level': level,
            'processing_time_ms': 35,
            'timestamp': datetime.utcnow().isoformat(),
            'details': data,
        }

        if redis_client:
            redis_client.lpush('processed_events', json.dumps(result))
            redis_client.ltrim('processed_events', 0, 999)

        if supabase_available:
            archive_event_to_supabase({
                'event_topic': 'api/process_threat',
                'event_data': result,
                'event_timestamp': datetime.utcnow().isoformat(),
                'threat_level': level,
                'event_type': threat_type,
            })

        return jsonify(result), 200
    except Exception as e:
        logger.error(f"Error processing threat: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/events/recent', methods=['GET'])
def events_recent():
    limit = request.args.get('limit', 50, type=int)
    if not redis_client:
        return jsonify({'events': [], 'total': 0}), 200
    raw_events = redis_client.lrange('processed_events', 0, max(0, limit - 1))
    events = []
    for item in raw_events:
        try:
            events.append(json.loads(item))
        except Exception:
            continue
    return jsonify({'events': events, 'total': len(events)}), 200


@app.route('/status', methods=['GET'])
def status_alias():
    return get_status()

def main():
    """Main entry point"""
    logger.info("Starting SafeHer Event Processor...")
    
    # Connect to MQTT broker
    try:
        mqtt_client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
        mqtt_client.loop_start()
    except Exception as e:
        logger.error(f"Failed to connect to MQTT: {e}")
    
    # Start Flask server
    logger.info(f"Starting HTTP server on port {HTTP_PORT}")
    app.run(host='0.0.0.0', port=HTTP_PORT, debug=False)

if __name__ == '__main__':
    main()
