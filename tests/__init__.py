"""
SafeHer Test Suite Configuration
"""

import sys
from pathlib import Path

# Add project root to Python path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

# Test configuration
TEST_CONFIG = {
    'API_BASE_URL': 'http://localhost:5000',
    'TEST_USER_EMAIL': 'test@safeherapp.com',
    'TEST_USER_PASSWORD': 'TestPass123!',
    'ADMIN_EMAIL': 'admin@safeherapp.com',
    'ADMIN_PASSWORD': 'admin123',
}
