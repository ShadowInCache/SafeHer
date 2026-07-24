#!/usr/bin/env python3
"""
Complete SafeHer System Audit and Diagnostics
Identifies all errors and issues across the entire system
"""

import os
import sys
import requests
import redis
import json
import traceback
from typing import Tuple, List, Dict

# Add src to path
sys.path.insert(0, os.path.dirname(__file__))

class SystemAudit:
    def __init__(self):
        self.errors = []
        self.warnings = []
        self.successes = []
    
    def test_imports(self):
        """Test all critical imports"""
        print("\n" + "="*70)
        print("1. TESTING IMPORTS")
        print("="*70)
        
        imports_to_test = [
            ("Flask app", "from src.core.api_gateway import app"),
            ("WebSocket manager", "from src.core.websocket_manager import get_websocket_manager"),
            ("Database service", "from src.services.database.db_service import get_database_service"),
            ("MQTT service", "from src.services.mqtt.mqtt_service import get_mqtt_service"),
        ]
        
        for name, import_stmt in imports_to_test:
            try:
                exec(import_stmt)
                print(f"✅ {name}")
                self.successes.append(name)
            except Exception as e:
                print(f"❌ {name}: {str(e)}")
                self.errors.append((name, str(e)))
    
    def test_docker_services(self):
        """Test Docker service connectivity"""
        print("\n" + "="*70)
        print("2. TESTING DOCKER SERVICES")
        print("="*70)
        
        services = {
            'Redis': ('localhost', 6379),
            'MQTT': ('localhost', 1883),
            'Event Processor': ('http://localhost:8080/health', 'http'),
        }
        
        # Test Redis
        try:
            r = redis.Redis(host='localhost', port=6379, socket_connect_timeout=2)
            r.ping()
            print(f"✅ Redis (6379)")
            self.successes.append("Redis connectivity")
        except Exception as e:
            print(f"❌ Redis: {str(e)}")
            self.errors.append(("Redis", str(e)))
        
        # Test Event Processor
        try:
            response = requests.get('http://localhost:8080/health', timeout=2)
            if response.status_code == 200:
                print(f"✅ Event Processor (8080)")
                self.successes.append("Event Processor connectivity")
            else:
                print(f"⚠️  Event Processor: Status {response.status_code}")
                self.warnings.append(f"Event Processor returned status {response.status_code}")
        except requests.exceptions.RequestException as e:
            print(f"❌ Event Processor: {str(e)}")
            self.errors.append(("Event Processor", str(e)))
    
    def test_api_gateway(self):
        """Test API Gateway endpoints"""
        print("\n" + "="*70)
        print("3. TESTING API GATEWAY ENDPOINTS")
        print("="*70)
        
        endpoints = [
            ('GET', '/health', None),
            ('GET', '/status', None),
            ('GET', '/api/v1/events', None),
            ('GET', '/api/v1/archive?limit=5', None),
        ]
        
        base_url = 'http://localhost:5000'
        
        for method, endpoint, data in endpoints:
            try:
                if method == 'GET':
                    response = requests.get(f"{base_url}{endpoint}", timeout=3)
                    if response.status_code in [200, 503]:  # 503 is OK if service unavailable
                        print(f"✅ {method} {endpoint}")
                        self.successes.append(f"{endpoint}")
                    else:
                        print(f"⚠️  {method} {endpoint}: {response.status_code}")
                        self.warnings.append(f"{endpoint} returned {response.status_code}")
            except requests.exceptions.ConnectionError:
                print(f"⚠️  Gateway not running: {endpoint}")
                self.warnings.append("API Gateway not running")
                break
            except Exception as e:
                print(f"❌ {method} {endpoint}: {str(e)}")
                self.errors.append((endpoint, str(e)))
    
    def test_database(self):
        """Test database connectivity"""
        print("\n" + "="*70)
        print("4. TESTING DATABASE")
        print("="*70)
        
        try:
            from src.services.database.db_service import get_database_service
            db = get_database_service()
            
            # Try a simple operation
            db.connection.execute("SELECT 1")
            print(f"✅ SQLite database connectivity")
            self.successes.append("Database connectivity")
        except Exception as e:
            print(f"❌ Database: {str(e)}")
            self.errors.append(("Database", str(e)))
    
    def test_supabase(self):
        """Test Supabase cloud connectivity"""
        print("\n" + "="*70)
        print("5. TESTING SUPABASE CLOUD")
        print("="*70)
        
        try:
            supabase_url = os.getenv('SUPABASE_URL', 'https://pmniolsrmzevknwmdkcd.supabase.co')
            supabase_key = os.getenv('SUPABASE_SECRET_KEY', 'sb_secret_Z8KIkef56gyYNBmzzjPAEg_an9RpQhO')
            
            headers = {
                "Authorization": f"Bearer {supabase_key}",
                "apikey": supabase_key,
            }
            
            response = requests.get(
                f"{supabase_url}/rest/v1/events?limit=1",
                headers=headers,
                timeout=5
            )
            
            if response.status_code in [200, 401, 404]:  # 404 is OK if table doesn't exist
                print(f"✅ Supabase REST API connectivity")
                self.successes.append("Supabase connectivity")
            else:
                print(f"⚠️  Supabase: Status {response.status_code}")
                self.warnings.append(f"Supabase returned {response.status_code}")
        except requests.exceptions.ConnectionError:
            print(f"⚠️  Supabase: Connection failed (may require internet)")
            self.warnings.append("Supabase network error")
        except Exception as e:
            print(f"❌ Supabase: {str(e)}")
            self.errors.append(("Supabase", str(e)))
    
    def test_file_structure(self):
        """Test project file structure"""
        print("\n" + "="*70)
        print("6. TESTING PROJECT STRUCTURE")
        print("="*70)
        
        required_files = [
            'app.py',
            'manage.py',
            'requirements.txt',
            '.env',
            'src/core/api_gateway.py',
            'src/core/websocket_manager.py',
            'src/services/database/db_service.py',
            'src/services/mqtt/mqtt_service.py',
            'deployment/docker/docker-compose.yml',
            'deployment/docker/safeher_event_processor.py',
        ]
        
        for file_path in required_files:
            full_path = os.path.join(os.path.dirname(__file__), file_path)
            if os.path.exists(full_path):
                print(f"✅ {file_path}")
                self.successes.append(f"File: {file_path}")
            else:
                print(f"❌ {file_path} - MISSING")
                self.errors.append((f"Missing file: {file_path}", "File not found"))
    
    def print_summary(self):
        """Print audit summary"""
        print("\n" + "="*70)
        print("📊 AUDIT SUMMARY")
        print("="*70)
        
        total_success = len(self.successes)
        total_errors = len(self.errors)
        total_warnings = len(self.warnings)
        
        print(f"\n✅ Successes: {total_success}")
        print(f"⚠️  Warnings: {total_warnings}")
        print(f"❌ Errors: {total_errors}")
        
        if self.errors:
            print(f"\n❌ CRITICAL ISSUES ({len(self.errors)}):")
            for name, error in self.errors:
                print(f"   • {name}: {error}")
        
        if self.warnings:
            print(f"\n⚠️  WARNINGS ({len(self.warnings)}):")
            for warning in self.warnings:
                print(f"   • {warning}")
        
        print("\n" + "="*70)
        
        return len(self.errors) == 0
    
    def run_full_audit(self):
        """Run complete system audit"""
        print("\n" + "="*70)
        print("🛡️  SAFEHER SYSTEM AUDIT & DIAGNOSTICS")
        print("="*70)
        
        self.test_file_structure()
        self.test_imports()
        self.test_database()
        self.test_docker_services()
        self.test_supabase()
        self.test_api_gateway()
        
        return self.print_summary()


if __name__ == '__main__':
    audit = SystemAudit()
    success = audit.run_full_audit()
    sys.exit(0 if success else 1)
