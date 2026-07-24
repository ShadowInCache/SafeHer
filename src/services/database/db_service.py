#!/usr/bin/env python3
"""
SafeHer Database Service Layer
Handles all database operations with connection pooling and error handling
Supports SQLite for development and PostgreSQL for production
"""

import json
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, asdict
import sqlite3
from pathlib import Path
import os

logger = logging.getLogger(__name__)


# IMPORTANT: This legacy service is deprecated in favor of the unified SQLAlchemy models and Alembic migrations
# located under fastapi_app. The tables defined here no longer match the unified schema. Avoid using this service
# in new code paths; migrate callers to the FastAPI data layer. If instantiated, this class will raise to prevent
# silent schema drift and data corruption.


@dataclass
class EmergencyContact:
    """Emergency contact data model"""
    contact_id: str
    user_id: str
    name: str
    phone_number: str
    email: Optional[str] = None
    relationship: str = "friend"
    priority: int = 1  # 1 = primary, 2 = secondary, 3 = backup
    created_at: str = None
    updated_at: str = None


@dataclass
class Incident:
    """Incident/threat event data model"""
    incident_id: str
    user_id: str
    threat_level: str  # low, medium, high, critical
    threat_type: str  # motion, weapon, voice, panic
    location: Dict[str, float]  # {lat, lng}
    timestamp: str
    description: str
    evidence_data: Dict[str, Any]
    resolved: bool = False
    resolution_time: Optional[str] = None
    emergency_contacts_notified: List[str] = None


@dataclass
class Device:
    """Connected device data model"""
    device_id: str
    user_id: str
    device_type: str  # glove, glasses
    device_name: str
    mac_address: str
    firmware_version: str
    is_paired: bool = True
    is_connected: bool = False
    battery_level: int = 100
    last_seen: str = None
    created_at: str = None


class DatabaseService:
    """
    Database service for SafeHer
    Provides CRUD operations for users, contacts, incidents, and devices
    """

    def __init__(self, db_url: Optional[str] = None):
        """
        Initialize database service
        
        Args:
            db_url: Database URL (sqlite:///safeher.db or postgresql://...)
                   If None, uses SQLite with default location
        """
        raise RuntimeError(
            "Legacy DatabaseService is deprecated. Use the unified FastAPI SQLAlchemy data layer and Alembic migrations instead."
        )

    def _initialize_database(self):
        """Initialize database tables if they don't exist"""
        if self.is_sqlite:
            db_path = self.db_url.replace("sqlite:///", "")
        else:
            # PostgreSQL - fallback to SQLite if not available
            logger.warning("⚠️ PostgreSQL not configured, using SQLite fallback")
            db_path = "safeher.db"
        
        os.makedirs(os.path.dirname(db_path) if os.path.dirname(db_path) else ".", exist_ok=True)
        self.connection = sqlite3.connect(db_path)
        self.connection.row_factory = sqlite3.Row

        self._create_tables()

    def _create_tables(self):
        """Create all required tables"""
        cursor = self.connection.cursor()

        # Users table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                user_id TEXT PRIMARY KEY,
                email TEXT UNIQUE NOT NULL,
                name TEXT NOT NULL,
                phone_number TEXT,
                profile_photo_url TEXT,
                emergency_mode_active BOOLEAN DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)

        # Emergency contacts table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS emergency_contacts (
                contact_id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                name TEXT NOT NULL,
                phone_number TEXT NOT NULL,
                email TEXT,
                relationship TEXT DEFAULT 'friend',
                priority INTEGER DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
            )
        """)

        # Devices table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS devices (
                device_id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                device_type TEXT NOT NULL,
                device_name TEXT NOT NULL,
                mac_address TEXT NOT NULL,
                firmware_version TEXT,
                is_paired BOOLEAN DEFAULT 1,
                is_connected BOOLEAN DEFAULT 0,
                battery_level INTEGER DEFAULT 100,
                last_seen TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
            )
        """)

        # Incidents table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS incidents (
                incident_id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                threat_level TEXT NOT NULL,
                threat_type TEXT NOT NULL,
                location_lat REAL,
                location_lng REAL,
                timestamp TEXT NOT NULL,
                description TEXT,
                evidence_data TEXT,
                resolved BOOLEAN DEFAULT 0,
                resolution_time TEXT,
                emergency_contacts_notified TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
            )
        """)

        # Threat events table (for analytics)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS threat_events (
                event_id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                incident_id TEXT,
                threat_type TEXT NOT NULL,
                confidence REAL,
                threat_level TEXT,
                timestamp TEXT NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
                FOREIGN KEY (incident_id) REFERENCES incidents(incident_id) ON DELETE CASCADE
            )
        """)

        self.connection.commit()
        logger.info("✅ Database tables created/verified")

    # =====================================================================
    # USER OPERATIONS
    # =====================================================================

    def create_user(self, user_id: str, email: str, name: str, 
                   phone_number: Optional[str] = None) -> Dict[str, Any]:
        """Create new user"""
        try:
            cursor = self.connection.cursor()
            now = datetime.utcnow().isoformat()
            
            cursor.execute("""
                INSERT INTO users 
                (user_id, email, name, phone_number, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (user_id, email, name, phone_number, now, now))
            
            self.connection.commit()
            logger.info(f"✅ User created: {user_id}")
            return {'status': 'success', 'user_id': user_id}
        except Exception as e:
            logger.error(f"❌ Error creating user: {e}")
            return {'status': 'error', 'message': str(e)}

    def get_user(self, user_id: str) -> Optional[Dict[str, Any]]:
        """Get user by ID"""
        try:
            cursor = self.connection.cursor()
            cursor.execute("SELECT * FROM users WHERE user_id = ?", (user_id,))
            row = cursor.fetchone()
            return dict(row) if row else None
        except Exception as e:
            logger.error(f"❌ Error getting user: {e}")
            return None

    # =====================================================================
    # EMERGENCY CONTACT OPERATIONS
    # =====================================================================

    def add_emergency_contact(self, contact_id: str, user_id: str, name: str,
                             phone_number: str, email: Optional[str] = None,
                             relationship: str = "friend", 
                             priority: int = 1) -> Dict[str, Any]:
        """Add emergency contact for user"""
        try:
            cursor = self.connection.cursor()
            now = datetime.utcnow().isoformat()
            
            cursor.execute("""
                INSERT INTO emergency_contacts
                (contact_id, user_id, name, phone_number, email, relationship, priority, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (contact_id, user_id, name, phone_number, email, relationship, priority, now, now))
            
            self.connection.commit()
            logger.info(f"✅ Emergency contact added: {contact_id}")
            return {'status': 'success', 'contact_id': contact_id}
        except Exception as e:
            logger.error(f"❌ Error adding contact: {e}")
            return {'status': 'error', 'message': str(e)}

    def get_emergency_contacts(self, user_id: str) -> List[Dict[str, Any]]:
        """Get all emergency contacts for user, sorted by priority"""
        try:
            cursor = self.connection.cursor()
            cursor.execute("""
                SELECT * FROM emergency_contacts 
                WHERE user_id = ? 
                ORDER BY priority ASC
            """, (user_id,))
            rows = cursor.fetchall()
            return [dict(row) for row in rows]
        except Exception as e:
            logger.error(f"❌ Error getting contacts: {e}")
            return []

    def update_emergency_contact(self, contact_id: str, **kwargs) -> Dict[str, Any]:
        """Update emergency contact"""
        try:
            cursor = self.connection.cursor()
            kwargs['updated_at'] = datetime.utcnow().isoformat()
            
            updates = ", ".join([f"{k} = ?" for k in kwargs.keys()])
            values = list(kwargs.values()) + [contact_id]
            
            cursor.execute(f"UPDATE emergency_contacts SET {updates} WHERE contact_id = ?", values)
            self.connection.commit()
            logger.info(f"✅ Contact updated: {contact_id}")
            return {'status': 'success'}
        except Exception as e:
            logger.error(f"❌ Error updating contact: {e}")
            return {'status': 'error', 'message': str(e)}

    def delete_emergency_contact(self, contact_id: str) -> Dict[str, Any]:
        """Delete emergency contact"""
        try:
            cursor = self.connection.cursor()
            cursor.execute("DELETE FROM emergency_contacts WHERE contact_id = ?", (contact_id,))
            self.connection.commit()
            logger.info(f"✅ Contact deleted: {contact_id}")
            return {'status': 'success'}
        except Exception as e:
            logger.error(f"❌ Error deleting contact: {e}")
            return {'status': 'error', 'message': str(e)}

    # =====================================================================
    # DEVICE OPERATIONS
    # =====================================================================

    def register_device(self, device_id: str, user_id: str, device_type: str,
                       device_name: str, mac_address: str,
                       firmware_version: str) -> Dict[str, Any]:
        """Register new device"""
        try:
            cursor = self.connection.cursor()
            now = datetime.utcnow().isoformat()
            
            cursor.execute("""
                INSERT INTO devices
                (device_id, user_id, device_type, device_name, mac_address, firmware_version, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (device_id, user_id, device_type, device_name, mac_address, firmware_version, now))
            
            self.connection.commit()
            logger.info(f"✅ Device registered: {device_id}")
            return {'status': 'success', 'device_id': device_id}
        except Exception as e:
            logger.error(f"❌ Error registering device: {e}")
            return {'status': 'error', 'message': str(e)}

    def get_user_devices(self, user_id: str) -> List[Dict[str, Any]]:
        """Get all devices for user"""
        try:
            cursor = self.connection.cursor()
            cursor.execute("SELECT * FROM devices WHERE user_id = ? ORDER BY created_at DESC", (user_id,))
            rows = cursor.fetchall()
            return [dict(row) for row in rows]
        except Exception as e:
            logger.error(f"❌ Error getting devices: {e}")
            return []

    def update_device_status(self, device_id: str, is_connected: bool, 
                            battery_level: int) -> Dict[str, Any]:
        """Update device status (connection, battery)"""
        try:
            cursor = self.connection.cursor()
            now = datetime.utcnow().isoformat()
            
            cursor.execute("""
                UPDATE devices 
                SET is_connected = ?, battery_level = ?, last_seen = ?
                WHERE device_id = ?
            """, (is_connected, battery_level, now, device_id))
            
            self.connection.commit()
            return {'status': 'success'}
        except Exception as e:
            logger.error(f"❌ Error updating device: {e}")
            return {'status': 'error', 'message': str(e)}

    # =====================================================================
    # INCIDENT OPERATIONS
    # =====================================================================

    def create_incident(self, incident_id: str, user_id: str, threat_level: str,
                       threat_type: str, location: Dict[str, float],
                       description: str, evidence_data: Dict[str, Any]) -> Dict[str, Any]:
        """Create new incident"""
        try:
            cursor = self.connection.cursor()
            now = datetime.utcnow().isoformat()
            
            cursor.execute("""
                INSERT INTO incidents
                (incident_id, user_id, threat_level, threat_type, location_lat, location_lng,
                 timestamp, description, evidence_data, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (incident_id, user_id, threat_level, threat_type, 
                  location.get('lat'), location.get('lng'),
                  now, description, json.dumps(evidence_data), now))
            
            self.connection.commit()
            logger.info(f"✅ Incident created: {incident_id}")
            return {'status': 'success', 'incident_id': incident_id}
        except Exception as e:
            logger.error(f"❌ Error creating incident: {e}")
            return {'status': 'error', 'message': str(e)}

    def get_incident_history(self, user_id: str, limit: int = 100,
                            days: int = 30) -> List[Dict[str, Any]]:
        """Get user's incident history"""
        try:
            cursor = self.connection.cursor()
            cutoff_date = (datetime.utcnow() - timedelta(days=days)).isoformat()
            
            cursor.execute("""
                SELECT * FROM incidents 
                WHERE user_id = ? AND timestamp > ?
                ORDER BY timestamp DESC
                LIMIT ?
            """, (user_id, cutoff_date, limit))
            
            rows = cursor.fetchall()
            return [dict(row) for row in rows]
        except Exception as e:
            logger.error(f"❌ Error getting incident history: {e}")
            return []

    def get_incident(self, incident_id: str) -> Optional[Dict[str, Any]]:
        """Get specific incident"""
        try:
            cursor = self.connection.cursor()
            cursor.execute("SELECT * FROM incidents WHERE incident_id = ?", (incident_id,))
            row = cursor.fetchone()
            return dict(row) if row else None
        except Exception as e:
            logger.error(f"❌ Error getting incident: {e}")
            return None

    def resolve_incident(self, incident_id: str) -> Dict[str, Any]:
        """Mark incident as resolved"""
        try:
            cursor = self.connection.cursor()
            now = datetime.utcnow().isoformat()
            
            cursor.execute("""
                UPDATE incidents 
                SET resolved = 1, resolution_time = ?
                WHERE incident_id = ?
            """, (now, incident_id))
            
            self.connection.commit()
            return {'status': 'success'}
        except Exception as e:
            logger.error(f"❌ Error resolving incident: {e}")
            return {'status': 'error', 'message': str(e)}

    def log_threat_event(self, event_id: str, user_id: str, threat_type: str,
                        confidence: float, threat_level: str,
                        incident_id: Optional[str] = None) -> Dict[str, Any]:
        """Log individual threat event for analytics"""
        try:
            cursor = self.connection.cursor()
            now = datetime.utcnow().isoformat()
            
            cursor.execute("""
                INSERT INTO threat_events
                (event_id, user_id, incident_id, threat_type, confidence, threat_level, timestamp)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (event_id, user_id, incident_id, threat_type, confidence, threat_level, now))
            
            self.connection.commit()
            return {'status': 'success', 'event_id': event_id}
        except Exception as e:
            logger.error(f"❌ Error logging threat event: {e}")
            return {'status': 'error', 'message': str(e)}

    # =====================================================================
    # ANALYTICS OPERATIONS
    # =====================================================================

    def get_threat_statistics(self, user_id: str, days: int = 30) -> Dict[str, Any]:
        """Get threat statistics for user"""
        try:
            cursor = self.connection.cursor()
            cutoff_date = (datetime.utcnow() - timedelta(days=days)).isoformat()
            
            # Total incidents
            cursor.execute("""
                SELECT COUNT(*) as count FROM incidents 
                WHERE user_id = ? AND timestamp > ?
            """, (user_id, cutoff_date))
            total_incidents = cursor.fetchone()['count']
            
            # Incidents by threat level
            cursor.execute("""
                SELECT threat_level, COUNT(*) as count FROM incidents 
                WHERE user_id = ? AND timestamp > ?
                GROUP BY threat_level
            """, (user_id, cutoff_date))
            by_level = {row['threat_level']: row['count'] for row in cursor.fetchall()}
            
            # Incidents by threat type
            cursor.execute("""
                SELECT threat_type, COUNT(*) as count FROM incidents 
                WHERE user_id = ? AND timestamp > ?
                GROUP BY threat_type
            """, (user_id, cutoff_date))
            by_type = {row['threat_type']: row['count'] for row in cursor.fetchall()}
            
            return {
                'total_incidents': total_incidents,
                'by_level': by_level,
                'by_type': by_type,
                'period_days': days
            }
        except Exception as e:
            logger.error(f"❌ Error getting statistics: {e}")
            return {}

    def close(self):
        """Close database connection"""
        if self.connection:
            self.connection.close()
            logger.info("✅ Database connection closed")


# Singleton instance
_database_service = None


def get_database_service(db_url: Optional[str] = None) -> DatabaseService:
    """Get or create database service singleton"""
    global _database_service
    if _database_service is None:
        _database_service = DatabaseService(db_url)
    return _database_service
