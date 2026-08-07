#!/usr/bin/env python3
"""
SafeHer WebSocket Manager
Handles real-time bidirectional communication between mobile app and backend
Manages connections, message routing, and connection stability
"""

import json
import logging
import threading
import time
from datetime import datetime, timedelta
from typing import Dict, Set, Callable, Optional, Any
from dataclasses import dataclass, asdict
from queue import Queue

logger = logging.getLogger(__name__)


@dataclass
class WebSocketConnection:
    """Represents a WebSocket connection"""
    user_id: str
    connection_id: str
    connected_at: datetime
    last_heartbeat: datetime
    message_queue: Queue
    subscribed_topics: Set[str]
    is_active: bool = True


class WebSocketManager:
    """
    Manages WebSocket connections and message routing
    Handles connection lifecycle, subscriptions, and message queuing
    """

    def __init__(self, heartbeat_interval: int = 30, connection_timeout: int = 90):
        """
        Initialize WebSocket Manager
        
        Args:
            heartbeat_interval: Seconds between heartbeat pings
            connection_timeout: Seconds before declaring connection dead
        """
        self.heartbeat_interval = heartbeat_interval
        self.connection_timeout = connection_timeout

        # Connection management
        self.connections: Dict[str, WebSocketConnection] = {}
        self.user_connections: Dict[str, Set[str]] = {}  # user_id -> connection_ids
        self.lock = threading.RLock()

        # Message handlers
        self.message_handlers: Dict[str, Callable] = {}

        # Statistics
        self.stats = {
            'total_connections': 0,
            'active_connections': 0,
            'messages_sent': 0,
            'messages_received': 0,
            'heartbeats_sent': 0,
            'timeout_disconnects': 0
        }

        # Start background threads
        self._start_maintenance_threads()

        logger.info("✅ WebSocket Manager initialized")

    def register_connection(self, user_id: str, connection_id: str) -> WebSocketConnection:
        """Register a new WebSocket connection"""
        with self.lock:
            now = datetime.utcnow()
            connection = WebSocketConnection(
                user_id=user_id,
                connection_id=connection_id,
                connected_at=now,
                last_heartbeat=now,
                message_queue=Queue(maxsize=1000),  # Bounded queue
                subscribed_topics=set()
            )

            self.connections[connection_id] = connection

            if user_id not in self.user_connections:
                self.user_connections[user_id] = set()
            self.user_connections[user_id].add(connection_id)

            self.stats['total_connections'] += 1
            self.stats['active_connections'] += 1

            logger.info(f"✅ WebSocket registered: {connection_id} for user {user_id}")
            return connection

    def unregister_connection(self, connection_id: str) -> bool:
        """Unregister and close a WebSocket connection"""
        with self.lock:
            if connection_id not in self.connections:
                return False

            conn = self.connections.pop(connection_id)
            
            if conn.user_id in self.user_connections:
                self.user_connections[conn.user_id].discard(connection_id)
                if not self.user_connections[conn.user_id]:
                    del self.user_connections[conn.user_id]

            self.stats['active_connections'] = max(0, self.stats['active_connections'] - 1)
            logger.info(f"✅ WebSocket unregistered: {connection_id}")
            return True

    def subscribe_to_topic(self, connection_id: str, topic: str) -> bool:
        """Subscribe connection to a topic"""
        with self.lock:
            if connection_id not in self.connections:
                logger.warning(f"⚠️ Connection {connection_id} not found")
                return False

            self.connections[connection_id].subscribed_topics.add(topic)
            logger.debug(f"✅ Connection {connection_id} subscribed to {topic}")
            return True

    def subscribe_user_to_topic(self, user_id: str, topic: str) -> int:
        """Subscribe all connections for a user to a topic"""
        count = 0
        with self.lock:
            if user_id in self.user_connections:
                for conn_id in self.user_connections[user_id]:
                    self.connections[conn_id].subscribed_topics.add(topic)
                    count += 1
        return count

    def unsubscribe_from_topic(self, connection_id: str, topic: str) -> bool:
        """Unsubscribe connection from a topic"""
        with self.lock:
            if connection_id not in self.connections:
                return False

            self.connections[connection_id].subscribed_topics.discard(topic)
            return True

    def send_message(self, connection_id: str, message: Dict[str, Any]) -> bool:
        """
        Queue a message for sending to a specific connection
        
        Args:
            connection_id: Target connection ID
            message: Message dictionary (will be JSON encoded)
        
        Returns:
            True if queued successfully, False if connection not found or queue full
        """
        with self.lock:
            if connection_id not in self.connections:
                logger.warning(f"⚠️ Connection {connection_id} not found for message")
                return False

            conn = self.connections[connection_id]

            try:
                # Add timestamp if not present
                if 'timestamp' not in message:
                    message['timestamp'] = datetime.utcnow().isoformat()

                # Try to queue with timeout
                conn.message_queue.put(message, timeout=1.0)
                self.stats['messages_sent'] += 1
                logger.debug(f"📤 Message queued for {connection_id}")
                return True

            except Exception as e:
                logger.error(f"❌ Failed to queue message for {connection_id}: {e}")
                return False

    def broadcast_to_user(self, user_id: str, message: Dict[str, Any]) -> int:
        """
        Send message to all connections for a user
        
        Returns:
            Number of connections message was queued for
        """
        count = 0
        with self.lock:
            if user_id in self.user_connections:
                for conn_id in self.user_connections[user_id]:
                    if self.send_message(conn_id, message):
                        count += 1
        return count

    def broadcast_to_topic_subscribers(self, topic: str, message: Dict[str, Any]) -> int:
        """
        Send message to all connections subscribed to a topic
        
        Returns:
            Number of connections message was queued for
        """
        count = 0
        with self.lock:
            for conn_id, conn in self.connections.items():
                if topic in conn.subscribed_topics:
                    if self.send_message(conn_id, message):
                        count += 1
        return count

    def get_message(self, connection_id: str, timeout: float = 0.1) -> Optional[Dict[str, Any]]:
        """
        Get next message from queue for a connection
        Non-blocking with timeout
        """
        with self.lock:
            if connection_id not in self.connections:
                return None

            conn = self.connections[connection_id]

        try:
            message = conn.message_queue.get(timeout=timeout)
            return message
        except:
            return None

    def update_heartbeat(self, connection_id: str) -> bool:
        """Update last heartbeat timestamp for connection"""
        with self.lock:
            if connection_id not in self.connections:
                return False

            self.connections[connection_id].last_heartbeat = datetime.utcnow()
            return True

    def register_message_handler(self, message_type: str, handler: Callable) -> None:
        """Register handler for specific message type"""
        self.message_handlers[message_type] = handler
        logger.info(f"✅ Registered handler for message type: {message_type}")

    def handle_incoming_message(self, connection_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Handle incoming message from client
        
        Returns:
            Response to send back to client
        """
        try:
            message_type = data.get('type', 'unknown')

            # Update heartbeat on activity
            self.update_heartbeat(connection_id)
            self.stats['messages_received'] += 1

            logger.debug(f"📨 Received {message_type} from {connection_id}")

            # Call registered handler if exists
            if message_type in self.message_handlers:
                response = self.message_handlers[message_type](connection_id, data)
                return response
            else:
                return {'status': 'error', 'message': f'Unknown message type: {message_type}'}

        except Exception as e:
            logger.error(f"❌ Error handling message: {e}")
            return {'status': 'error', 'message': str(e)}

    def _start_maintenance_threads(self):
        """Start background maintenance threads"""
        # Heartbeat thread
        heartbeat_thread = threading.Thread(target=self._heartbeat_loop, daemon=True)
        heartbeat_thread.start()

        # Connection cleanup thread
        cleanup_thread = threading.Thread(target=self._cleanup_loop, daemon=True)
        cleanup_thread.start()

        logger.info("✅ WebSocket maintenance threads started")

    def _heartbeat_loop(self):
        """Send periodic heartbeats to all connections"""
        while True:
            try:
                time.sleep(self.heartbeat_interval)

                with self.lock:
                    for conn_id, conn in list(self.connections.items()):
                        if conn.is_active:
                            # Queue heartbeat message
                            heartbeat = {
                                'type': 'heartbeat',
                                'timestamp': datetime.utcnow().isoformat(),
                                'connection_id': conn_id
                            }
                            conn.message_queue.put(heartbeat, block=False)
                            self.stats['heartbeats_sent'] += 1

                logger.debug(f"💓 Sent {self.stats['heartbeats_sent']} heartbeats")

            except Exception as e:
                logger.error(f"❌ Error in heartbeat loop: {e}")

    def _cleanup_loop(self):
        """Remove stale connections (no heartbeat)"""
        while True:
            try:
                time.sleep(self.connection_timeout // 2)  # Check twice per timeout period

                now = datetime.utcnow()
                timeout_duration = timedelta(seconds=self.connection_timeout)
                stale_connections = []

                with self.lock:
                    for conn_id, conn in list(self.connections.items()):
                        if now - conn.last_heartbeat > timeout_duration:
                            stale_connections.append(conn_id)

                # Remove stale connections
                for conn_id in stale_connections:
                    self.unregister_connection(conn_id)
                    self.stats['timeout_disconnects'] += 1
                    logger.warning(f"⚠️ Removed stale connection: {conn_id}")

            except Exception as e:
                logger.error(f"❌ Error in cleanup loop: {e}")

    def get_status(self) -> Dict[str, Any]:
        """Get WebSocket manager status"""
        with self.lock:
            user_count = len(self.user_connections)
            conn_list = list(self.connections.keys())

        return {
            'connections': len(conn_list),
            'connection_ids': conn_list,
            'users': user_count,
            'stats': self.stats.copy()
        }

    def get_user_connections(self, user_id: str) -> list:
        """Get all connection IDs for a user"""
        with self.lock:
            return list(self.user_connections.get(user_id, []))


# Singleton instance
_ws_manager = None
_ws_lock = threading.RLock()


def get_websocket_manager() -> WebSocketManager:
    """Get or create WebSocket manager singleton"""
    global _ws_manager
    with _ws_lock:
        if _ws_manager is None:
            _ws_manager = WebSocketManager()
        return _ws_manager
