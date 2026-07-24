"""
API Gateway Tests
Test the main API Gateway endpoints and functionality
"""

import unittest
import requests
from tests import TEST_CONFIG


class TestAPIGateway(unittest.TestCase):
    """Test API Gateway endpoints"""
    
    @classmethod
    def setUpClass(cls):
        cls.base_url = TEST_CONFIG['API_BASE_URL']
        cls.admin_token = None
        
    def test_health_check(self):
        """Test API health check endpoint"""
        try:
            response = requests.get(f"{self.base_url}/api/v1/health", timeout=5)
            self.assertEqual(response.status_code, 200)
            data = response.json()
            self.assertIn('status', data)
        except requests.ConnectionError:
            self.skipTest("API Gateway not running")
    
    def test_api_versioning(self):
        """Test versioned OpenAPI endpoint"""
        try:
            response = requests.get(f"{self.base_url}/api/v1/openapi.json", timeout=5)
            self.assertEqual(response.status_code, 200)
            data = response.json()
            self.assertIn('paths', data)
        except requests.ConnectionError:
            self.skipTest("API Gateway not running")
    
    def test_repeated_health_stability(self):
        """Test repeated health checks stay successful"""
        try:
            for i in range(5):
                response = requests.get(f"{self.base_url}/api/v1/health", timeout=5)
                self.assertEqual(response.status_code, 200, f"health failed on iteration {i}")
        except requests.ConnectionError:
            self.skipTest("API Gateway not running")


if __name__ == '__main__':
    unittest.main()
