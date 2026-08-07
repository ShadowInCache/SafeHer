#!/usr/bin/env python3
"""
SafeHer MQTT Service Layer
Handles all MQTT communication between devices, cloud, and mobile app
Manages subscriptions, message routing, and quality of service
"""

import json
import logging
import time
import threading
from datetime import datetime
from typing import Dict, List, Callable, Optional, Any
import paho.mqtt.client as mqtt

logger = logging.getLogger(__name__)


class MQTTService:
    """
    MQTT Service for SafeHer
    Manages connections, subscriptions, and message routing
    Single instance per process (thread-safe)
    """

    def __init__(self, broker_host: str = "localhost", broker_port: int = 1883,
                 use_tls: bool = False, ca_certs: Optional[str] = None):
        """
        Initialize MQTT Service
        
        Args:
            broker_host: MQTT broker hostname
            broker_port: MQTT broker port (1883 for plain, 8883 for TLS)
            use_tls: Whether to use TLS encryption
            ca_certs: Path to CA certificate file (if using TLS)
        """
        self.broker_host = broker_host
        self.broker_port = broker_port
        self.use_tls = use_tls
        self.ca_certs = ca_certs

        # MQTT client
        self.client = mqtt.Client(client_id=f"safeher_backend_{int(time.time())}")
        self.client.on_connect = self._on_connect
        self.client.on_disconnect = self._on_disconnect
        self.client.on_message = self._on_message
        self.client.on_subscribe = self._on_subscribe

        # Connection state
        self.is_connected = False
        self.reconnect_attempts = 0
        self.max_reconnect_attempts = 10
        self.reconnect_delay = 1  # seconds, will exponentially backoff

        # Message callbacks (topic -> callback function)
        self.callbacks: Dict[str, List[Callable]] = {}
        
        # Thread safety
        self.lock = threading.RLock()

        # Statistics
        self.stats = {
            'messages_published': 0,
            'messages_received': 0,
            'subscriptions': 0,
            'connect_count': 0,
            'disconnect_count': 0,
            'last_activity': None
        }

        # Connect to broker
        self._connect()
        logger.info(f"✅ MQTT Service initialized: {broker_host}:{broker_port}")

    def _connect(self):
        """Connect to MQTT broker with automatic reconnection"""
        try:
            if self.use_tls and self.ca_certs:
                self.client.tls_set(ca_certs=self.ca_certs)
                self.client.tls_insecure = False

            logger.info(f"🔌 Connecting to MQTT broker: {self.broker_host}:{self.broker_port}")
            self.client.connect(self.broker_host, self.broker_port, keepalive=60)
            self.client.loop_start()  # Start background thread for message loop
            logger.info("✅ MQTT client started")

        except Exception as e:
            logger.error(f"❌ Failed to connect to MQTT broker: {e}")
            self._schedule_reconnect()

    def _on_connect(self, client, userdata, flags, rc):
        """Callback when MQTT client connects"""
        if rc == 0:
            self.is_connected = True
            self.reconnect_attempts = 0
            self.reconnect_delay = 1
            self.stats['connect_count'] += 1
            logger.info("✅ Connected to MQTT broker")

            # Resubscribe to all topics
            self._resubscribe_all()
        else:
            logger.error(f"❌ MQTT connection failed with code: {rc}")
            self._schedule_reconnect()

    def _on_disconnect(self, client, userdata, rc):
        """Callback when MQTT client disconnects"""
        self.is_connected = False
        self.stats['disconnect_count'] += 1
        
        if rc != 0:
            logger.warning(f"⚠️ Unexpected MQTT disconnect with code: {rc}")
            self._schedule_reconnect()
        else:
            logger.info("✅ Gracefully disconnected from MQTT broker")

    def _on_message(self, client, userdata, msg):
        """Callback when MQTT message is received"""
        try:
            self.stats['last_activity'] = datetime.utcnow().isoformat()
            self.stats['messages_received'] += 1

            topic = msg.topic
            payload = msg.payload.decode('utf-8')

            logger.debug(f"📨 MQTT message received on {topic}: {payload[:100]}...")

            # Parse payload
            try:
                data = json.loads(payload)
            except json.JSONDecodeError:
                data = {'raw_payload': payload}

            # Call all registered callbacks for this topic
            with self.lock:
                if topic in self.callbacks:
                    for callback in self.callbacks[topic]:
                        try:
                            callback(topic, data)
                        except Exception as e:
                            logger.error(f"❌ Error in MQTT callback for {topic}: {e}")
                
                # Also call wildcard callbacks (topics ending with #)
                for registered_topic in self.callbacks:
                    if registered_topic.endswith('#'):
                        # Check if message matches this wildcard topic
                        if self._matches_wildcard(topic, registered_topic):
                            for callback in self.callbacks[registered_topic]:
                                try:
                                    callback(topic, data)
                                except Exception as e:
                                    logger.error(f"❌ Error in MQTT wildcard callback: {e}")

        except Exception as e:
            logger.error(f"❌ Error processing MQTT message: {e}")

    def _on_subscribe(self, client, userdata, mid, granted_qos):
        """Callback when MQTT subscription is confirmed"""
        logger.debug(f"✅ MQTT subscription confirmed with QoS: {granted_qos}")

    def _schedule_reconnect(self):
        """Schedule reconnection with exponential backoff"""
        self.reconnect_attempts += 1
        if self.reconnect_attempts > self.max_reconnect_attempts:
            logger.error(f"❌ Max reconnection attempts ({self.max_reconnect_attempts}) exceeded")
            return

        delay = min(self.reconnect_delay * (2 ** (self.reconnect_attempts - 1)), 300)  # Max 5 min
        logger.warning(f"⚠️ Scheduling reconnect in {delay} seconds (attempt {self.reconnect_attempts})")
        time.sleep(delay)
        self._connect()

    def _resubscribe_all(self):
        """Resubscribe to all registered topics"""
        with self.lock:
            for topic in self.callbacks.keys():
                self.client.subscribe(topic, qos=1)
                logger.debug(f"📡 Resubscribed to: {topic}")

    @staticmethod
    def _matches_wildcard(topic: str, wildcard_topic: str) -> bool:
        """Check if topic matches wildcard pattern"""
        if wildcard_topic.endswith('#'):
            prefix = wildcard_topic[:-2]
            return topic.startswith(prefix)
        return topic == wildcard_topic

    # =====================================================================
    # PUBLIC METHODS - PUBLISHING
    # =====================================================================

    def publish_motion_data(self, user_id: str, device_id: str,
                          motion_data: Dict[str, Any]) -> bool:
        """Publish motion data from glove to cloud"""
        return self.publish(
            topic=f"devices/{user_id}/glove/motion",
            data=motion_data,
            qos=1
        )

    def publish_weapon_detection(self, user_id: str, device_id: str,
                                weapon_data: Dict[str, Any]) -> bool:
        """Publish weapon detection from glasses to cloud"""
        return self.publish(
            topic=f"devices/{user_id}/glasses/weapon",
            data=weapon_data,
            qos=2  # QoS 2 = guaranteed delivery
        )

    def publish_voice_detection(self, user_id: str, device_id: str,
                               voice_data: Dict[str, Any]) -> bool:
        """Publish voice analysis from glasses to cloud"""
        return self.publish(
            topic=f"devices/{user_id}/glasses/voice",
            data=voice_data,
            qos=2
        )

    def publish_threat_alert(self, user_id: str, threat_data: Dict[str, Any]) -> bool:
        """Publish unified threat alert to user"""
        return self.publish(
            topic=f"threats/{user_id}",
            data=threat_data,
            qos=2  # QoS 2 = guaranteed delivery for critical alerts
        )

    def publish_emergency_alert(self, user_id: str, emergency_data: Dict[str, Any]) -> bool:
        """Publish emergency alert (high priority)"""
        return self.publish(
            topic=f"emergencies/{user_id}",
            data=emergency_data,
            qos=2
        )

    def publish_device_command(self, device_id: str, command: Dict[str, Any]) -> bool:
        """Send command to device (e.g., restart, calibrate)"""
        return self.publish(
            topic=f"commands/{device_id}",
            data=command,
            qos=1
        )

    def publish_device_status_request(self, device_id: str) -> bool:
        """Request device to report status"""
        return self.publish(
            topic=f"commands/{device_id}",
            data={'command': 'status_report'},
            qos=1
        )

    def publish(self, topic: str, data: Dict[str, Any], qos: int = 1) -> bool:
        """
        Generic publish method
        
        Args:
            topic: MQTT topic
            data: Data to publish (will be JSON encoded)
            qos: Quality of Service (0, 1, or 2)
        
        Returns:
            True if published successfully, False otherwise
        """
        try:
            if not self.is_connected:
                logger.warning(f"⚠️ Not connected to MQTT, cannot publish to {topic}")
                return False

            payload = json.dumps(data)
            result = self.client.publish(topic, payload, qos=qos)

            if result.rc == mqtt.MQTT_ERR_SUCCESS:
                self.stats['messages_published'] += 1
                self.stats['last_activity'] = datetime.utcnow().isoformat()
                logger.debug(f"📤 Published to {topic}: {payload[:100]}...")
                return True
            else:
                logger.error(f"❌ Failed to publish to {topic}: {mqtt.error_string(result.rc)}")
                return False

        except Exception as e:
            logger.error(f"❌ Error publishing to {topic}: {e}")
            return False

    # =====================================================================
    # PUBLIC METHODS - SUBSCRIBING
    # =====================================================================

    def subscribe_motion_data(self, user_id: str, callback: Callable) -> bool:
        """Subscribe to motion data from user's glove"""
        return self.subscribe(
            topic=f"devices/{user_id}/glove/motion",
            callback=callback,
            qos=1
        )

    def subscribe_weapon_detection(self, user_id: str, callback: Callable) -> bool:
        """Subscribe to weapon detection from user's glasses"""
        return self.subscribe(
            topic=f"devices/{user_id}/glasses/weapon",
            callback=callback,
            qos=1
        )

    def subscribe_voice_detection(self, user_id: str, callback: Callable) -> bool:
        """Subscribe to voice detection from user's glasses"""
        return self.subscribe(
            topic=f"devices/{user_id}/glasses/voice",
            callback=callback,
            qos=1
        )

    def subscribe_user_devices(self, user_id: str, callback: Callable) -> bool:
        """Subscribe to all device data from user"""
        return self.subscribe(
            topic=f"devices/{user_id}/#",
            callback=callback,
            qos=1
        )

    def subscribe_device_status(self, device_id: str, callback: Callable) -> bool:
        """Subscribe to status from specific device"""
        return self.subscribe(
            topic=f"devices/{device_id}/status",
            callback=callback,
            qos=1
        )

    def subscribe_device_responses(self, device_id: str, callback: Callable) -> bool:
        """Subscribe to command responses from device"""
        return self.subscribe(
            topic=f"responses/{device_id}/#",
            callback=callback,
            qos=1
        )

    def subscribe(self, topic: str, callback: Callable, qos: int = 1) -> bool:
        """
        Generic subscribe method
        
        Args:
            topic: MQTT topic pattern (can include +, # wildcards)
            callback: Function to call when message received
                     Signature: callback(topic, data)
            qos: Quality of Service (0 or 1)
        
        Returns:
            True if subscribed successfully
        """
        try:
            with self.lock:
                # Register callback
                if topic not in self.callbacks:
                    self.callbacks[topic] = []
                self.callbacks[topic].append(callback)

                # Subscribe to topic
                if self.is_connected:
                    result = self.client.subscribe(topic, qos=qos)
                    if result[0] == mqtt.MQTT_ERR_SUCCESS:
                        self.stats['subscriptions'] += 1
                        logger.info(f"✅ Subscribed to: {topic}")
                        return True
                    else:
                        logger.error(f"❌ Failed to subscribe to {topic}: {mqtt.error_string(result[0])}")
                        return False
                else:
                    logger.warning(f"⚠️ Not connected, will subscribe to {topic} when connected")
                    return True  # Will subscribe on reconnect

        except Exception as e:
            logger.error(f"❌ Error subscribing to {topic}: {e}")
            return False

    def unsubscribe(self, topic: str, callback: Optional[Callable] = None) -> bool:
        """Unsubscribe from topic (or remove specific callback)"""
        try:
            with self.lock:
                if callback is None:
                    # Remove all callbacks for this topic
                    if topic in self.callbacks:
                        del self.callbacks[topic]
                else:
                    # Remove specific callback
                    if topic in self.callbacks and callback in self.callbacks[topic]:
                        self.callbacks[topic].remove(callback)

                # Unsubscribe if no more callbacks
                if topic not in self.callbacks or not self.callbacks[topic]:
                    if self.is_connected:
                        self.client.unsubscribe(topic)
                    logger.info(f"✅ Unsubscribed from: {topic}")
                    return True

        except Exception as e:
            logger.error(f"❌ Error unsubscribing from {topic}: {e}")
            return False

    # =====================================================================
    # STATUS & DIAGNOSTICS
    # =====================================================================

    def get_status(self) -> Dict[str, Any]:
        """Get MQTT service status"""
        return {
            'is_connected': self.is_connected,
            'broker': f"{self.broker_host}:{self.broker_port}",
            'subscriptions': list(self.callbacks.keys()),
            'subscription_count': len(self.callbacks),
            'stats': self.stats.copy()
        }

    def is_online(self) -> bool:
        """Check if MQTT is connected"""
        return self.is_connected

    def get_stats(self) -> Dict[str, Any]:
        """Get detailed statistics"""
        return self.stats.copy()

    # =====================================================================
    # CLEANUP
    # =====================================================================

    def disconnect(self):
        """Gracefully disconnect from MQTT broker"""
        try:
            if self.is_connected:
                self.client.loop_stop()
                self.client.disconnect()
                logger.info("✅ MQTT service disconnected")
        except Exception as e:
            logger.error(f"❌ Error disconnecting from MQTT: {e}")

    def __del__(self):
        """Cleanup on deletion"""
        self.disconnect()


# Singleton instance
_mqtt_service = None
_mqtt_lock = threading.RLock()


def get_mqtt_service(broker_host: str = "localhost", broker_port: int = 1883,
                     use_tls: bool = False, ca_certs: Optional[str] = None) -> MQTTService:
    """Get or create MQTT service singleton"""
    global _mqtt_service
    with _mqtt_lock:
        if _mqtt_service is None:
            _mqtt_service = MQTTService(broker_host, broker_port, use_tls, ca_certs)
        return _mqtt_service
