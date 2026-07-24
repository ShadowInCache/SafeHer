"""
SafeHer Simplified API Gateway
Lightweight backend that integrates with the unified event processor
Connects mobile app → Event Processor → Database
"""

from flask import Flask, request, jsonify, Response
from flask_cors import CORS
import requests
import logging
import redis
from datetime import datetime
import os
from dotenv import load_dotenv
import json
from flask_sock import Sock
import uuid

# Import WebSocket manager and Database service
from src.core.websocket_manager import WebSocketManager, get_websocket_manager
from src.services.database.db_service import get_database_service, DatabaseService

# Load environment variables
load_dotenv()

app = Flask(__name__)
CORS(app)  # Enable CORS for mobile app
sock = Sock(app)  # WebSocket support

# Logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize WebSocket manager for real-time communication
ws_manager: WebSocketManager = get_websocket_manager()

# Initialize Database service
db_service: DatabaseService = get_database_service(
    db_url=os.getenv('DATABASE_URL', 'sqlite:///safeher.db')
)

# ============================================================================
# SIMPLIFIED CONFIGURATION - Only connects to unified event processor
# ============================================================================
EVENT_PROCESSOR_URL = os.getenv('EVENT_PROCESSOR_URL', 'http://localhost:8080')

# Redis for real-time data and pub/sub
redis_client = redis.Redis(
    host=os.getenv('REDIS_HOST', 'localhost'),
    port=int(os.getenv('REDIS_PORT', '6379')),
    decode_responses=True
)

# ============================================================================
# HEALTH CHECK - Simplified to only check event processor
# ============================================================================
@app.route('/health', methods=['GET'])
def health():
    """Gateway health check"""
    try:
        # Check event processor (non-blocking)
        try:
            processor_response = requests.get(f"{EVENT_PROCESSOR_URL}/health", timeout=2)
            processor_healthy = processor_response.status_code == 200
        except requests.RequestException as e:
            logger.warning(f"Event processor health check failed: {str(e)}")
            processor_healthy = False
        
        # Check Redis (non-blocking)
        try:
            redis_client.ping()
            redis_healthy = True
        except redis.RedisError as e:
            logger.warning(f"Redis health check failed: {str(e)}")
            redis_healthy = False
        
        services_status = {
            'gateway': 'healthy',
            'event_processor': 'healthy' if processor_healthy else 'unavailable',
            'redis': 'healthy' if redis_healthy else 'unavailable',
        }
        
        # Gateway is healthy if at least it can run
        gateway_healthy = True
        
        response_data = {
            'status': 'healthy' if gateway_healthy else 'degraded',
            'services': services_status,
            'timestamp': datetime.now().isoformat(),
            'architecture': 'simplified_event_driven',
            'mode': 'standalone' if not processor_healthy else 'full'
        }
        
        return jsonify(response_data), 200
        
    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': str(e),
            'timestamp': datetime.now().isoformat()
        }), 500


def _check_event_processor_health():
    """Check if event processor is healthy"""
    try:
        response = requests.get(f"{EVENT_PROCESSOR_URL}/health", timeout=2)
        return 'healthy' if response.status_code == 200 else 'unhealthy'
    except:
        return 'unavailable'


@app.route('/status', methods=['GET'])
def status():
    """Simple status endpoint"""
    return jsonify({
        'status': 'running',
        'service': 'safeher-api-gateway',
        'version': '1.0.0',
        'timestamp': datetime.now().isoformat(),
        'uptime': 'unknown'
    }), 200


# ============================================================================
# WEBSOCKET ENDPOINT - Real-time threat alerts for mobile app
# ============================================================================

@sock.route('/ws/alerts/<user_id>')
def alerts_websocket(ws, user_id):
    """
    WebSocket endpoint for real-time threat alerts
    Mobile app connects here to receive live threat notifications
    
    URI: ws://server:port/ws/alerts/{user_id}
    """
    connection_id = str(uuid.uuid4())
    
    try:
        logger.info(f"📲 WebSocket connection established for user {user_id} (ID: {connection_id})")
        
        # Register connection with manager
        conn = ws_manager.register_connection(user_id, connection_id)
        
        if not conn:
            logger.error(f"Failed to register WebSocket connection")
            ws.close()
            return
        
        # Subscribe to threat alerts topic
        ws_manager.subscribe_to_topic(connection_id, f"user_alerts:{user_id}")
        ws_manager.subscribe_to_topic(connection_id, "threat_alerts")  # Global threats
        
        logger.info(f"✅ User {user_id} subscribed to alert topics")
        
        # Keep connection alive and forward messages
        while True:
            try:
                # Receive message from client (ping/heartbeat)
                data = ws.receive(timeout=30)  # 30 second timeout
                
                if data:
                    try:
                        msg_data = json.loads(data)
                        
                        # Handle different message types
                        if msg_data.get('type') == 'ping':
                            # Client heartbeat
                            ws_manager.update_heartbeat(connection_id)
                            ws.send(json.dumps({'type': 'pong', 'timestamp': datetime.now().isoformat()}))
                            
                        elif msg_data.get('type') == 'subscribe':
                            # Subscribe to additional topics
                            topic = msg_data.get('topic')
                            if topic:
                                ws_manager.subscribe_to_topic(connection_id, topic)
                                ws.send(json.dumps({'type': 'subscribed', 'topic': topic}))
                    
                    except json.JSONDecodeError:
                        logger.warning(f"Invalid JSON from client: {data}")
                
                # Check for queued messages to send to client
                message = ws_manager.get_message(connection_id, timeout=0.1)
                if message:
                    ws.send(json.dumps(message))
                    
            except Exception as e:
                if "timeout" in str(e).lower():
                    # Timeout - update heartbeat and continue
                    ws_manager.update_heartbeat(connection_id)
                    continue
                else:
                    logger.warning(f"WebSocket receive error: {e}")
                    break
        
    except Exception as e:
        logger.error(f"❌ WebSocket error for user {user_id}: {e}")
    finally:
        # Cleanup on disconnect
        ws_manager.unregister_connection(connection_id)
        logger.info(f"🔌 WebSocket disconnected for user {user_id}")
        ws.close()


@app.route('/api/v1/alerts/broadcast', methods=['POST'])
def broadcast_alert():
    """
    Broadcast alert to all connected users
    Used by event processor to push alerts via WebSocket
    
    Input: {
        alert_id: str,
        type: str,
        user_ids: list[str] or None (None = broadcast to all),
        message: str,
        severity: str,
        ...
    }
    """
    try:
        alert_data = request.json
        
        user_ids = alert_data.get('user_ids')
        
        if user_ids:
            # Send to specific users
            for user_id in user_ids:
                count = ws_manager.broadcast_to_user(user_id, alert_data)
                logger.info(f"Alert sent to {count} connections for user {user_id}")
        else:
            # Broadcast to all connected users on threat_alerts topic
            count = ws_manager.broadcast_to_topic_subscribers('threat_alerts', alert_data)
            logger.info(f"Alert broadcasted to {count} total connections")
        
        return jsonify({
            'status': 'broadcast',
            'alert_id': alert_data.get('alert_id'),
            'timestamp': datetime.now().isoformat()
        }), 200
        
    except Exception as e:
        logger.error(f"Broadcast error: {e}")
        return jsonify({'error': str(e)}), 500


# ============================================================================

@app.route('/api/v1/process-threat', methods=['POST'])
def process_threat():
    """
    Process any type of threat data through unified event processor
    Replaces separate motion/weapon/voice endpoints
    
    Input: {
        device_id: str,
        user_id: str,
        type: str,  # 'motion', 'image', 'audio', 'panic'
        data: dict, # sensor data or media
        location: dict (optional)
    }
    Output: {
        status: str,
        threat_detected: bool,
        confidence: float,
        threat_level: str,
        response_actions: list
    }
    """
    try:
        input_data = request.json
        
        # Forward to event processor
        response = requests.post(
            f"{EVENT_PROCESSOR_URL}/process_threat",
            json={
                'device_id': input_data.get('device_id', 'unknown'),
                'user_id': input_data.get('user_id', 'unknown'),
                'type': input_data.get('type', 'unknown'),
                'data': input_data.get('data', {}),
                'location': input_data.get('location')
            },
            timeout=15
        )
        
        result = response.json()
        
        # Store alert for mobile app if threat detected
        if result.get('threat_detected', False):
            _store_alert_for_user(input_data.get('user_id'), result)
        
        return jsonify(result), response.status_code
        
    except requests.exceptions.RequestException as e:
        logger.error(f"Event processor error: {e}")
        return jsonify({'error': 'Event processor unavailable'}), 503
    except Exception as e:
        logger.error(f"Threat processing error: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/alerts/<user_id>', methods=['GET'])
def get_user_alerts(user_id):
    """Get recent alerts for a user"""
    try:
        # Get alerts from Redis
        alerts = redis_client.lrange(f'user_alerts:{user_id}', 0, 9)  # Last 10 alerts
        parsed_alerts = [json.loads(alert) for alert in alerts]
        
        return jsonify({
            'alerts': parsed_alerts,
            'count': len(parsed_alerts)
        })
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/events/recent', methods=['GET'])
def get_recent_events():
    """Get recent threat events from event processor"""
    try:
        response = requests.get(f"{EVENT_PROCESSOR_URL}/events/recent", timeout=5)
        return jsonify(response.json()), response.status_code
        
    except requests.exceptions.RequestException as e:
        logger.error(f"Event processor error: {e}")
        return jsonify({'error': 'Event processor unavailable'}), 503
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# ============================================================================
# LEGACY ENDPOINT COMPATIBILITY (for existing mobile app)
# ============================================================================

@app.route('/api/v1/ml/motion-detection', methods=['POST'])
def motion_detection_legacy():
    """Legacy motion detection endpoint - redirects to unified processor"""
    try:
        data = request.json
        unified_data = {
            'device_id': data.get('deviceId', 'unknown'),
            'user_id': data.get('userId', 'unknown'),
            'type': 'motion_data',
            'data': data,
            'location': data.get('location')
        }
        
        response = requests.post(
            f"{EVENT_PROCESSOR_URL}/process_threat",
            json=unified_data,
            timeout=10
        )
        
        result = response.json()
        
        # Convert to legacy format
        legacy_result = {
            'prediction': 1 if result.get('threat_detected', False) else 0,
            'confidence': result.get('confidence', 0),
            'threatLevel': result.get('threat_level', 'low'),
            'processingTime': result.get('processing_time_ms', 0)
        }
        
        return jsonify(legacy_result), response.status_code
        
    except Exception as e:
        logger.error(f"Legacy motion detection error: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/ml/weapon-detection', methods=['POST'])
def weapon_detection_legacy():
    """Legacy weapon detection endpoint - redirects to unified processor"""
    try:
        data = request.json
        unified_data = {
            'device_id': data.get('deviceId', 'unknown'),
            'user_id': data.get('userId', 'unknown'),
            'type': 'image_data',
            'data': data,
            'location': data.get('location')
        }
        
        response = requests.post(
            f"{EVENT_PROCESSOR_URL}/process_threat",
            json=unified_data,
            timeout=15
        )
        
        result = response.json()
        
        # Convert to legacy format
        legacy_result = {
            'detectionsFound': result.get('threat_detected', False),
            'detections': [{
                'class': result.get('weapon_type', 'unknown'),
                'confidence': result.get('confidence', 0),
                'bbox': result.get('bounding_box', [0,0,0,0])
            }] if result.get('threat_detected', False) else [],
            'processingTime': result.get('processing_time_ms', 0)
        }
        
        return jsonify(legacy_result), response.status_code
        
    except Exception as e:
        logger.error(f"Legacy weapon detection error: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/v1/ml/voice-detection', methods=['POST'])
def voice_detection_legacy():
    """Legacy voice detection endpoint - redirects to unified processor"""
    try:
        data = request.json
        unified_data = {
            'device_id': data.get('deviceId', 'unknown'),
            'user_id': data.get('userId', 'unknown'),
            'type': 'audio_data',
            'data': data,
            'location': data.get('location')
        }
        
        response = requests.post(
            f"{EVENT_PROCESSOR_URL}/process_threat",
            json=unified_data,
            timeout=15
        )
        
        result = response.json()
        
        # Convert to legacy format
        legacy_result = {
            'isThreat': result.get('threat_detected', False),
            'emotion': result.get('distress_type', 'neutral'),
            'confidence': result.get('confidence', 0),
            'processingTime': result.get('processing_time_ms', 0)
        }
        
        return jsonify(legacy_result), response.status_code
        
    except Exception as e:
        logger.error(f"Legacy voice detection error: {e}")
        return jsonify({'error': str(e)}), 500

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

def _store_alert_for_user(user_id: str, result: dict):
    """Store alert in Redis for user to retrieve and push via WebSocket"""
    try:
        alert_data = {
            'alert_id': f"alert_{int(datetime.now().timestamp() * 1000)}",
            'type': 'threat_alert',
            'severity': result.get('threat_level', 'medium'),
            'message': f"Threat detected with {result.get('confidence', 0):.1%} confidence",
            'confidence': result.get('confidence', 0),
            'timestamp': datetime.now().isoformat(),
            'details': result
        }
        
        # Store in Redis for fallback
        redis_client.lpush(f'user_alerts:{user_id}', json.dumps(alert_data))
        redis_client.expire(f'user_alerts:{user_id}', 3600)  # 1 hour expiry
        
        # Push via WebSocket to all connections for this user
        ws_manager.broadcast_to_user(user_id, alert_data)
        logger.info(f"✅ Alert stored and broadcasted to user {user_id} via WebSocket")
        
    except Exception as e:
        logger.error(f"Error storing/broadcasting alert: {e}")


@app.route('/api/v1/websocket/status', methods=['GET'])
def websocket_status():
    """
    Get WebSocket manager statistics
    Shows current connections, message counts, etc.
    """
    try:
        stats = ws_manager.get_statistics()
        return jsonify({
            'status': 'active',
            'websocket_stats': stats,
            'timestamp': datetime.now().isoformat()
        }), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/v1/websocket/health', methods=['GET'])
def websocket_health():
    """
    Health check for WebSocket manager
    Used by monitoring systems
    """
    try:
        stats = ws_manager.get_statistics()
        health_status = 'healthy' if stats.get('active_connections', 0) >= 0 else 'degraded'
        
        return jsonify({
            'status': health_status,
            'service': 'websocket_manager',
            'active_connections': stats.get('active_connections', 0),
            'total_messages_sent': stats.get('messages_sent', 0),
            'heartbeats': stats.get('heartbeats_sent', 0),
            'timestamp': datetime.now().isoformat()
        }), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500


# ============================================================================
# EMERGENCY CONTACTS ENDPOINTS
# ============================================================================

@app.route('/api/v1/emergency-contacts/<user_id>', methods=['GET'])
def get_emergency_contacts(user_id):
    """Get all emergency contacts for a user"""
    try:
        contacts = db_service.get_emergency_contacts(user_id)
        return jsonify({
            'status': 'success',
            'contacts': contacts,
            'count': len(contacts),
            'timestamp': datetime.now().isoformat()
        }), 200
    except Exception as e:
        logger.error(f"❌ Error getting emergency contacts: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/v1/emergency-contacts', methods=['POST'])
def add_emergency_contact():
    """Add a new emergency contact"""
    try:
        data = request.json
        user_id = data.get('user_id')
        name = data.get('name')
        phone_number = data.get('phone_number')
        email = data.get('email')
        relationship = data.get('relationship', 'friend')
        priority = data.get('priority', 1)
        
        # Validation
        if not all([user_id, name, phone_number]):
            return jsonify({
                'error': 'Missing required fields: user_id, name, phone_number'
            }), 400
        
        # Create unique contact ID
        contact_id = f"{user_id}_contact_{int(datetime.now().timestamp() * 1000)}"
        
        result = db_service.add_emergency_contact(
            contact_id=contact_id,
            user_id=user_id,
            name=name,
            phone_number=phone_number,
            email=email,
            relationship=relationship,
            priority=priority
        )
        
        if result['status'] == 'success':
            return jsonify({
                'status': 'success',
                'contact_id': contact_id,
                'message': 'Emergency contact added successfully',
                'timestamp': datetime.now().isoformat()
            }), 201
        else:
            return jsonify(result), 500
            
    except Exception as e:
        logger.error(f"❌ Error adding emergency contact: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/v1/emergency-contacts/<contact_id>', methods=['PUT'])
def update_emergency_contact(contact_id):
    """Update an emergency contact"""
    try:
        data = request.json
        
        # Prepare update data (exclude None values)
        update_data = {k: v for k, v in data.items() if v is not None}
        
        if not update_data:
            return jsonify({'error': 'No fields to update'}), 400
        
        result = db_service.update_emergency_contact(contact_id, **update_data)
        
        if result['status'] == 'success':
            return jsonify({
                'status': 'success',
                'message': 'Emergency contact updated successfully',
                'timestamp': datetime.now().isoformat()
            }), 200
        else:
            return jsonify(result), 500
            
    except Exception as e:
        logger.error(f"❌ Error updating emergency contact: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/v1/emergency-contacts/<contact_id>', methods=['DELETE'])
def delete_emergency_contact(contact_id):
    """Delete an emergency contact"""
    try:
        result = db_service.delete_emergency_contact(contact_id)
        
        if result['status'] == 'success':
            return jsonify({
                'status': 'success',
                'message': 'Emergency contact deleted successfully',
                'timestamp': datetime.now().isoformat()
            }), 200
        else:
            return jsonify(result), 500
            
    except Exception as e:
        logger.error(f"❌ Error deleting emergency contact: {e}")
        return jsonify({'error': str(e)}), 500


# ============================================================================
# SUPABASE ARCHIVE INTEGRATION ENDPOINTS
# ============================================================================

@app.route('/api/v1/archive', methods=['GET'])
def get_archived_events():
    """
    Retrieve archived events from Supabase via unified event processor
    
    Query Parameters:
    - limit: Maximum number of events to return (default: 100)
    - threat_level: Filter by threat level (low, medium, high, critical)
    - event_type: Filter by event type (motion, weapon, voice, panic)
    - user_id: Filter by user ID
    """
    try:
        limit = request.args.get('limit', 100, type=int)
        threat_level = request.args.get('threat_level', type=str)
        event_type = request.args.get('event_type', type=str)
        user_id = request.args.get('user_id', type=str)
        
        # Build query parameters
        params = {'limit': min(limit, 1000)}  # Cap at 1000
        if threat_level:
            params['threat_level'] = threat_level
        if event_type:
            params['event_type'] = event_type
        if user_id:
            params['user_id'] = user_id
        
        response = requests.get(
            f"{EVENT_PROCESSOR_URL}/api/archive",
            params=params,
            timeout=10
        )
        
        result = response.json()
        
        return jsonify({
            'status': 'success',
            'archived_events': result.get('archived_events', []),
            'total': result.get('total', 0),
            'source': 'supabase_rest_api',
            'filters': {
                'limit': limit,
                'threat_level': threat_level,
                'event_type': event_type,
                'user_id': user_id
            },
            'timestamp': datetime.now().isoformat()
        }), response.status_code
        
    except requests.exceptions.RequestException as e:
        logger.error(f"Event processor error: {e}")
        return jsonify({'error': 'Event processor unavailable'}), 503
    except Exception as e:
        logger.error(f"Archive retrieval error: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/v1/archive/post', methods=['POST'])
def manual_archive_event():
    """
    Manually archive an event to Supabase
    
    Input: {
        type: str (required),
        threat_level: str,
        topic: str,
        user_id: str,
        device_id: str,
        data: dict
    }
    """
    try:
        event_data = request.json
        
        if not event_data.get('type'):
            return jsonify({'error': 'Missing required field: type'}), 400
        
        response = requests.post(
            f"{EVENT_PROCESSOR_URL}/api/archive/post",
            json=event_data,
            timeout=10
        )
        
        result = response.json()
        
        return jsonify({
            'status': 'archived',
            'event': result.get('event'),
            'message': result.get('message'),
            'timestamp': datetime.now().isoformat()
        }), response.status_code
        
    except requests.exceptions.RequestException as e:
        logger.error(f"Event processor error: {e}")
        return jsonify({'error': 'Event processor unavailable'}), 503
    except Exception as e:
        logger.error(f"Manual archive error: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/v1/events', methods=['GET'])
def get_real_time_events():
    """
    Get real-time events from Redis stored in event processor
    
    Query Parameters:
    - limit: Maximum number of events to return (default: 50)
    - topic: Filter by MQTT topic
    """
    try:
        response = requests.get(
            f"{EVENT_PROCESSOR_URL}/api/events",
            params={'limit': request.args.get('limit', 50, type=int)},
            timeout=5
        )
        
        result = response.json()
        
        return jsonify({
            'status': 'success',
            'events': result.get('events', []),
            'total': result.get('total', 0),
            'source': 'redis_real_time',
            'timestamp': datetime.now().isoformat()
        }), response.status_code
        
    except requests.exceptions.RequestException as e:
        logger.error(f"Event processor error: {e}")
        return jsonify({'error': 'Event processor unavailable'}), 503
    except Exception as e:
        logger.error(f"Real-time events error: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/v1/shifts/<user_id>/events', methods=['GET'])
def get_shift_events(user_id):
    """
    Get threat events from a specific shift with timestamps
    
    Query Parameters:
    - start_time: ISO format timestamp (required)
    - end_time: ISO format timestamp (required)
    - threat_level: Filter by threat level (optional)
    """
    try:
        start_time = request.args.get('start_time')
        end_time = request.args.get('end_time')
        threat_level = request.args.get('threat_level')
        
        if not start_time or not end_time:
            return jsonify({
                'error': 'Missing required parameters: start_time, end_time'
            }), 400
        
        # Query archived events with time range
        response = requests.get(
            f"{EVENT_PROCESSOR_URL}/api/archive",
            params={
                'limit': 1000,
                'start_time': start_time,
                'end_time': end_time,
                'user_id': user_id,
                'threat_level': threat_level
            } if threat_level else {
                'limit': 1000,
                'start_time': start_time,
                'end_time': end_time,
                'user_id': user_id
            },
            timeout=10
        )
        
        result = response.json()
        events = result.get('archived_events', [])
        
        # Filter by timestamp if needed
        filtered_events = [
            e for e in events 
            if start_time <= e.get('event_timestamp', '') <= end_time
        ]
        
        return jsonify({
            'status': 'success',
            'user_id': user_id,
            'shift_window': {
                'start_time': start_time,
                'end_time': end_time
            },
            'events': filtered_events,
            'total': len(filtered_events),
            'threat_level_filter': threat_level,
            'timestamp': datetime.now().isoformat()
        }), 200
        
    except requests.exceptions.RequestException as e:
        logger.error(f"Event processor error: {e}")
        return jsonify({'error': 'Event processor unavailable'}), 503
    except Exception as e:
        logger.error(f"Shift events error: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/v1/events/clear', methods=['POST'])
def clear_real_time_events():
    """Clear Redis cache of real-time events"""
    try:
        response = requests.post(
            f"{EVENT_PROCESSOR_URL}/api/events/clear",
            timeout=5
        )
        
        result = response.json()
        
        return jsonify({
            'status': result.get('status', 'cleared'),
            'message': result.get('message'),
            'timestamp': datetime.now().isoformat()
        }), response.status_code
        
    except requests.exceptions.RequestException as e:
        logger.error(f"Event processor error: {e}")
        return jsonify({'error': 'Event processor unavailable'}), 503
    except Exception as e:
        logger.error(f"Clear events error: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/v1/processor/status', methods=['GET'])
def processor_status():
    """Get detailed status of the unified event processor"""
    try:
        response = requests.get(
            f"{EVENT_PROCESSOR_URL}/status",
            timeout=5
        )
        
        result = response.json()
        
        return jsonify({
            'status': 'operational',
            'processor': result,
            'gateway_timestamp': datetime.now().isoformat()
        }), response.status_code
        
    except requests.exceptions.RequestException as e:
        logger.error(f"Event processor unavailable: {e}")
        return jsonify({
            'status': 'unavailable',
            'message': 'Event processor is not responding',
            'gateway_timestamp': datetime.now().isoformat()
        }), 503
    except Exception as e:
        logger.error(f"Processor status error: {e}")
        return jsonify({'error': str(e)}), 500


if __name__ == '__main__':
    logger.info("🚀 Starting SafeHer Simplified API Gateway...")
    logger.info("📡 Event Processor URL: " + EVENT_PROCESSOR_URL)
    logger.info("🔄 Architecture: Simplified Event-Driven")
    
    app.run(
        host='0.0.0.0',
        port=int(os.getenv('PORT', 5000)),
        debug=os.getenv('DEBUG', 'False').lower() == 'true'
    )
