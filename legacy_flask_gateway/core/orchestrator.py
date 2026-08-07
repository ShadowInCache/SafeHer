#!/usr/bin/env python3
"""
SafeHer System Orchestrator
Hybrid Architecture Management Script
Manages the entire SafeHer ecosystem with intelligent coordination
"""

import asyncio
import logging
import json
import time
import subprocess
import sys
import os
from typing import Dict, List, Optional
from dataclasses import dataclass
from datetime import datetime
import redis
import requests
from concurrent.futures import ThreadPoolExecutor

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class ServiceStatus:
    """Service status information"""
    name: str
    status: str  # 'running', 'stopped', 'error', 'unknown'
    health: str  # 'healthy', 'unhealthy', 'unknown'
    url: Optional[str] = None
    last_check: Optional[str] = None
    response_time_ms: Optional[float] = None

class SafeHerOrchestrator:
    """
    SafeHer System Orchestrator
    Manages the simplified event-driven architecture
    """
    
    def __init__(self):
        # Simplified services - only 3 core services needed
        self.services = {
            'redis': {'port': 6379, 'health_endpoint': None},
            'mqtt': {'port': 1883, 'health_endpoint': None},
            'safeher_processor': {'port': 8080, 'health_endpoint': 'http://localhost:8080/health'},
        }
        
        # Redis connection for system coordination
        self.redis_client = None
        self.system_status = {}
        # Simplified startup sequence - just 3 services
        self.startup_sequence = [
            ['redis', 'mqtt'],           # Infrastructure layer
            ['safeher_processor']        # Unified processing layer
        ]
    
    def print_banner(self):
        """Print SafeHer system banner"""
        banner = """
╔════════════════════════════════════════════════════════════════════════╗
║                           🛡️  SafeHer System 🛡️                          ║
║                     Simplified Event-Driven Architecture                ║
║                                                                        ║
║  🏗️  Architecture: Single Event-Driven Processor                      ║
║  🔄  Communication: MQTT + Redis Event Bus                             ║
║  🤖  AI Engines: Unified ML Processing (Motion + Vision + Voice)       ║
║  📱  Edge Layer: ESP32 Smart Gloves + Glasses                          ║
║  🚨  Real-time: Emergency Response in <100ms                           ║
║                                                                        ║
║  ✅  3 Services Only: Redis + MQTT + Event Processor                   ║
╚════════════════════════════════════════════════════════════════════════╝
        """
        print(banner)
    
    def check_prerequisites(self) -> bool:
        """Check system prerequisites"""
        logger.info("🔍 Checking system prerequisites...")
        
        # Check Docker
        try:
            result = subprocess.run(['docker', '--version'], 
                                  capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                logger.info("✅ Docker is available")
            else:
                logger.error("❌ Docker not found")
                return False
        except Exception as e:
            logger.error(f"❌ Docker check failed: {e}")
            return False
        
        # Check Docker Compose
        try:
            result = subprocess.run(['docker-compose', '--version'], 
                                  capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                logger.info("✅ Docker Compose is available")
            else:
                logger.error("❌ Docker Compose not found")
                return False
        except Exception as e:
            logger.error(f"❌ Docker Compose check failed: {e}")
            return False
        
        # Check environment file
        if not os.path.exists('.env'):
            logger.warning("⚠️ .env file not found")
            if os.path.exists('.env.template'):
                logger.info("📋 Creating .env from template")
                subprocess.run(['cp', '.env.template', '.env'])
            else:
                logger.error("❌ No .env template found")
                return False
        
        logger.info("✅ Prerequisites check completed")
        return True
    
    async def start_system(self, mode: str = "production"):
        """Start the simplified SafeHer system"""
        logger.info(f"🚀 Starting simplified SafeHer system in {mode} mode...")
        
        # Use simplified compose file
        compose_files = ['-f', 'docker-compose.simple.yml']
        
        try:
            # Start infrastructure services first
            for service_group in self.startup_sequence:
                logger.info(f"🔧 Starting services: {', '.join(service_group)}")
                
                # Start services in this group
                cmd = ['docker-compose'] + compose_files + ['up', '-d'] + service_group
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
                
                if result.returncode != 0:
                    logger.error(f"❌ Failed to start {service_group}: {result.stderr}")
                    return False
                
                # Wait for services to be healthy
                await self.wait_for_services_health(service_group)
                
                logger.info(f"✅ Services started: {', '.join(service_group)}")
                time.sleep(5)  # Brief pause between groups
            
            # Initialize system state
            await self.initialize_system_state()
            
            logger.info("🎉 SafeHer system started successfully!")
            return True
            
        except Exception as e:
            logger.error(f"❌ System startup failed: {e}")
            return False
    
    async def wait_for_services_health(self, services: List[str], timeout: int = 120):
        """Wait for services to become healthy"""
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            all_healthy = True
            
            for service_name in services:
                status = await self.check_service_health(service_name)
                if status.health != 'healthy':
                    all_healthy = False
                    break
            
            if all_healthy:
                return True
            
            await asyncio.sleep(2)
        
        logger.warning(f"⚠️ Timeout waiting for services: {services}")
        return False
    
    async def check_service_health(self, service_name: str) -> ServiceStatus:
        """Check health of a specific service"""
        service_info = self.services.get(service_name)
        if not service_info:
            return ServiceStatus(service_name, 'unknown', 'unknown')
        
        try:
            # Check if service is running (Docker)
            result = subprocess.run(
                ['docker-compose', 'ps', '--services', '--filter', f'status=running'],
                capture_output=True, text=True, timeout=10
            )
            
            service_running = service_name in result.stdout
            
            if not service_running:
                return ServiceStatus(service_name, 'stopped', 'unhealthy')
            
            # Check health endpoint if available
            health_endpoint = service_info.get('health_endpoint')
            if health_endpoint:
                start_time = time.time()
                response = requests.get(health_endpoint, timeout=5)
                response_time = (time.time() - start_time) * 1000
                
                if response.status_code == 200:
                    health_data = response.json()
                    return ServiceStatus(
                        name=service_name,
                        status='running',
                        health='healthy',
                        url=health_endpoint,
                        last_check=datetime.now().isoformat(),
                        response_time_ms=response_time
                    )
                else:
                    return ServiceStatus(service_name, 'running', 'unhealthy', health_endpoint)
            else:
                # For services without health endpoints, assume healthy if running
                return ServiceStatus(service_name, 'running', 'healthy')
                
        except Exception as e:
            logger.debug(f"Health check failed for {service_name}: {e}")
            return ServiceStatus(service_name, 'unknown', 'unhealthy')
    
    async def check_system_health(self) -> Dict[str, ServiceStatus]:
        """Check health of all services"""
        logger.info("🔍 Checking system health...")
        
        status_dict = {}
        
        # Check all services concurrently
        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = {
                executor.submit(asyncio.run, self.check_service_health(service)): service 
                for service in self.services.keys()
            }
            
            for future in futures:
                service_name = futures[future]
                try:
                    status = future.result()
                    status_dict[service_name] = status
                except Exception as e:
                    logger.error(f"❌ Health check failed for {service_name}: {e}")
                    status_dict[service_name] = ServiceStatus(service_name, 'error', 'unhealthy')
        
        return status_dict
    
    async def initialize_system_state(self):
        """Initialize system state and connections"""
        logger.info("🔧 Initializing system state...")
        
        try:
            # Connect to Redis
            self.redis_client = redis.Redis(host='localhost', port=6379, decode_responses=True)
            self.redis_client.ping()
            logger.info("✅ Redis connection established")
            
            # Initialize system metadata
            system_metadata = {
                'startup_time': datetime.now().isoformat(),
                'version': '1.0.0',
                'architecture': 'hybrid_layered_event_driven',
                'services_count': len(self.services)
            }
            
            self.redis_client.hset('system:metadata', mapping=system_metadata)
            
            # Initialize service discovery
            for service_name, service_info in self.services.items():
                service_data = {
                    'port': service_info['port'],
                    'health_endpoint': service_info.get('health_endpoint', ''),
                    'status': 'initializing'
                }
                self.redis_client.hset(f'service:{service_name}', mapping=service_data)
            
            logger.info("✅ System state initialized")
            
        except Exception as e:
            logger.error(f"❌ System initialization failed: {e}")
    
    async def monitor_system(self, interval: int = 30):
        """Continuously monitor system health"""
        logger.info(f"👀 Starting system monitoring (interval: {interval}s)")
        
        while True:
            try:
                # Check all services
                status_dict = await self.check_system_health()
                
                # Update Redis with current status
                if self.redis_client:
                    for service_name, status in status_dict.items():
                        status_data = {
                            'status': status.status,
                            'health': status.health,
                            'last_check': status.last_check or datetime.now().isoformat(),
                            'response_time_ms': status.response_time_ms or 0
                        }
                        self.redis_client.hset(f'service:{service_name}:status', mapping=status_data)
                
                # Log system summary
                healthy_count = sum(1 for s in status_dict.values() if s.health == 'healthy')
                total_count = len(status_dict)
                
                if healthy_count == total_count:
                    logger.info(f"✅ System healthy: {healthy_count}/{total_count} services running")
                else:
                    logger.warning(f"⚠️ System degraded: {healthy_count}/{total_count} services healthy")
                
                # Check for unhealthy services
                unhealthy_services = [name for name, status in status_dict.items() 
                                    if status.health == 'unhealthy']
                if unhealthy_services:
                    logger.warning(f"🚨 Unhealthy services: {', '.join(unhealthy_services)}")
                
                await asyncio.sleep(interval)
                
            except Exception as e:
                logger.error(f"❌ Monitoring error: {e}")
                await asyncio.sleep(interval)
    
    def stop_system(self):
        """Stop the entire SafeHer system"""
        logger.info("🛑 Stopping SafeHer system...")
        
        try:
            # Stop all services
            result = subprocess.run(
                ['docker-compose', 'down'], 
                capture_output=True, text=True, timeout=60
            )
            
            if result.returncode == 0:
                logger.info("✅ SafeHer system stopped successfully")
                return True
            else:
                logger.error(f"❌ Failed to stop system: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"❌ System shutdown failed: {e}")
            return False
    
    def restart_service(self, service_name: str):
        """Restart a specific service"""
        logger.info(f"🔄 Restarting service: {service_name}")
        
        try:
            # Stop service
            subprocess.run(['docker-compose', 'stop', service_name], timeout=30)
            
            # Start service
            result = subprocess.run(
                ['docker-compose', 'up', '-d', service_name], 
                capture_output=True, text=True, timeout=60
            )
            
            if result.returncode == 0:
                logger.info(f"✅ Service restarted: {service_name}")
                return True
            else:
                logger.error(f"❌ Failed to restart {service_name}: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"❌ Service restart failed: {e}")
            return False
    
    async def display_system_dashboard(self):
        """Display real-time system dashboard"""
        while True:
            try:
                # Clear screen
                os.system('clear' if os.name == 'posix' else 'cls')
                
                # Print header
                self.print_banner()
                
                # Get current system status
                status_dict = await self.check_system_health()
                
                print("\n📊 SYSTEM STATUS DASHBOARD")
                print("=" * 80)
                
                # Service status table
                print(f"{'Service':<25} {'Status':<12} {'Health':<12} {'Response (ms)':<15}")
                print("-" * 80)
                
                for service_name, status in status_dict.items():
                    status_icon = "🟢" if status.health == "healthy" else "🔴" if status.health == "unhealthy" else "🟡"
                    response_time = f"{status.response_time_ms:.1f}" if status.response_time_ms else "N/A"
                    
                    print(f"{status_icon} {service_name:<22} {status.status:<12} {status.health:<12} {response_time:<15}")
                
                # System summary
                healthy_count = sum(1 for s in status_dict.values() if s.health == 'healthy')
                total_count = len(status_dict)
                health_percentage = (healthy_count / total_count) * 100 if total_count > 0 else 0
                
                print("\n📈 SYSTEM METRICS")
                print("-" * 40)
                print(f"System Health: {health_percentage:.1f}% ({healthy_count}/{total_count})")
                print(f"Uptime: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
                
                if self.redis_client:
                    try:
                        # Get system metrics from Redis
                        metadata = self.redis_client.hgetall('system:metadata')
                        if metadata:
                            startup_time = metadata.get('startup_time', 'Unknown')
                            print(f"Started: {startup_time}")
                    except:
                        pass
                
                print("\n💡 Press Ctrl+C to exit dashboard")
                
                await asyncio.sleep(5)  # Update every 5 seconds
                
            except KeyboardInterrupt:
                print("\n👋 Dashboard closed")
                break
            except Exception as e:
                logger.error(f"❌ Dashboard error: {e}")
                await asyncio.sleep(5)

async def main():
    """Main orchestrator function"""
    orchestrator = SafeHerOrchestrator()
    
    # Print banner
    orchestrator.print_banner()
    
    # Parse command line arguments
    if len(sys.argv) < 2:
        print("Usage: python orchestrator.py <command> [options]")
        print("\nCommands:")
        print("  start [production|development] - Start the system")
        print("  stop                          - Stop the system")
        print("  status                        - Check system status")
        print("  monitor                       - Start monitoring")
        print("  dashboard                     - Show real-time dashboard")
        print("  restart <service>             - Restart specific service")
        return
    
    command = sys.argv[1].lower()
    
    if command == "start":
        mode = sys.argv[2] if len(sys.argv) > 2 else "production"
        
        # Check prerequisites
        if not orchestrator.check_prerequisites():
            logger.error("❌ Prerequisites not met")
            return
        
        # Start system
        success = await orchestrator.start_system(mode)
        if success:
            print("\n🎉 SafeHer system started successfully!")
            print("\n📋 Next steps:")
            print("  • Monitor system: python orchestrator.py monitor")
            print("  • View dashboard: python orchestrator.py dashboard")
            print("  • Check status: python orchestrator.py status")
        else:
            print("\n❌ System startup failed")
    
    elif command == "stop":
        success = orchestrator.stop_system()
        if success:
            print("✅ SafeHer system stopped successfully")
        else:
            print("❌ System shutdown failed")
    
    elif command == "status":
        status_dict = await orchestrator.check_system_health()
        
        print("\n📊 SYSTEM STATUS")
        print("=" * 50)
        
        for service_name, status in status_dict.items():
            icon = "✅" if status.health == "healthy" else "❌"
            print(f"{icon} {service_name}: {status.status} / {status.health}")
    
    elif command == "monitor":
        await orchestrator.monitor_system()
    
    elif command == "dashboard":
        await orchestrator.display_system_dashboard()
    
    elif command == "restart":
        if len(sys.argv) < 3:
            print("❌ Please specify service name")
            return
        
        service_name = sys.argv[2]
        success = orchestrator.restart_service(service_name)
        if success:
            print(f"✅ Service {service_name} restarted successfully")
        else:
            print(f"❌ Failed to restart {service_name}")
    
    else:
        print(f"❌ Unknown command: {command}")

if __name__ == "__main__":
    asyncio.run(main())