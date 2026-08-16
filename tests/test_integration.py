"""
Integration Tests
End-to-end tests for the complete SafeHer system
"""

import unittest
import requests

# `RequestException` rather than `ConnectionError`: these files drive a live
# server over HTTP, and "the server is not there" is only one of the ways
# that fails. A managed Postgres that suspends when idle -- Neon's free tier
# does, after about five minutes -- makes the first request after a pause
# exceed the client timeout, which raises ReadTimeout. That is not a
# ConnectionError, so it escaped these handlers and failed the suite for a
# reason that had nothing to do with the code under test.
from uuid import uuid4
from tests import TEST_CONFIG


class TestEndToEnd(unittest.TestCase):
    """End-to-end integration tests"""
    
    @classmethod
    def setUpClass(cls):
        cls.base_url = TEST_CONFIG['API_BASE_URL']
        cls.access_token = None

        email = f"integration-{uuid4().hex}@safeherapp.com"
        password = TEST_CONFIG.get('TEST_USER_PASSWORD', 'TestPass123!')

        # Register and login a dedicated integration user.
        try:
            requests.post(
                f"{cls.base_url}/api/v1/auth/register",
                json={
                    'email': email,
                    'password': password,
                    'full_name': 'Integration User',
                    'role': 'user',
                },
                timeout=5
            )

            response = requests.post(
                f"{cls.base_url}/api/v1/auth/login",
                json={'email': email, 'password': password},
                timeout=5,
            )
            if response.status_code == 200:
                cls.access_token = response.json().get('access_token')
        except requests.RequestException:
            cls.access_token = None
    
    def test_user_registration_to_device_pairing(self):
        """Test complete flow: registration -> login -> device pairing"""
        try:
            email = f"pairing-{uuid4().hex}@safeherapp.com"
            password = TEST_CONFIG.get('TEST_USER_PASSWORD', 'TestPass123!')

            response = requests.post(
                f"{self.base_url}/api/v1/auth/register",
                json={
                    'email': email,
                    'password': password,
                    'full_name': 'Pairing Test User',
                    'role': 'user',
                },
                timeout=5
            )
            self.assertIn(response.status_code, [200, 201])

            login = requests.post(
                f"{self.base_url}/api/v1/auth/login",
                json={'email': email, 'password': password},
                timeout=5,
            )
            # Unlike the rest of the suite, this file talks to a live server
            # over HTTP, so `conftest.py` cannot isolate it -- the server runs
            # on the developer's own `.env`. With SMTP configured there, login
            # requires a code delivered to a real inbox, which this test has
            # no way to read. That is a property of the environment, not a
            # defect, so it skips rather than failing.
            if login.status_code == 403 and 'not verified' in login.text:
                self.skipTest(
                    "live server enforces email verification; this test cannot "
                    "receive the emailed code"
                )
            self.assertEqual(login.status_code, 200)
            token = login.json().get('access_token')
            self.assertTrue(token)

            device = requests.post(
                f"{self.base_url}/api/v1/devices/register",
                json={'device_name': f'esp32_{uuid4().hex[:8]}', 'device_type': 'glove'},
                headers={'Authorization': f'Bearer {token}'},
                timeout=5,
            )
            self.assertEqual(device.status_code, 200)
            self.assertIn('id', device.json())
        except requests.RequestException:
            self.skipTest("API Gateway not running")
    
    def test_threat_detection_to_alert(self):
        """Test flow: threat detected -> alert triggered -> contacts notified"""
        if not self.access_token:
            self.skipTest("Authentication failed")

        try:
            response = requests.post(
                f"{self.base_url}/api/v1/alerts/process-threat",
                json={
                    'device_id': 'safeher_glove_001',
                    'threat_type': 'motion_anomaly',
                    'confidence': 0.85,
                    'summary': 'Integration threat simulation',
                    'details': {'source': 'integration_test'},
                    'location': {'latitude': 12.9, 'longitude': 77.6},
                },
                headers={'Authorization': f'Bearer {self.access_token}'},
                timeout=5
            )

            if response.status_code == 503:
                self.skipTest("Event processor unavailable")

            self.assertEqual(response.status_code, 200)
            result = response.json()
            self.assertIn('threat_detected', result)
            self.assertIn('live_score', result)
        except requests.RequestException:
            self.skipTest("API Gateway not running")
    
    def test_device_data_to_incident_storage(self):
        """Test flow: device sends data -> processed -> stored as incident"""
        if not self.access_token:
            self.skipTest("Authentication failed")

        try:
            response = requests.post(
                f"{self.base_url}/api/v1/alerts/heartbeat",
                json={
                    'timestamp': '2026-04-03T00:00:00Z',
                    'threat_score': 32.5,
                    'location': {'latitude': 12.9, 'longitude': 77.6},
                },
                headers={'Authorization': f'Bearer {self.access_token}'},
                timeout=5
            )
            self.assertEqual(response.status_code, 202)

            live = requests.get(
                f"{self.base_url}/api/v1/alerts/live",
                headers={'Authorization': f'Bearer {self.access_token}'},
                timeout=5,
            )
            self.assertEqual(live.status_code, 200)
            self.assertIn('live_score', live.json())
        except requests.RequestException:
            self.skipTest("API Gateway not running")
    
    def test_sos_trigger_complete_flow(self):
        """Test SOS: trigger -> location sent -> contacts notified -> evidence stored"""
        if not self.access_token:
            self.skipTest("Authentication failed")

        try:
            response = requests.post(
                f"{self.base_url}/api/v1/alerts/emergency",
                json={
                    'summary': 'Integration SOS test',
                    'severity': 'critical',
                    'auto': False,
                    'location': {'latitude': 12.9, 'longitude': 77.6},
                    'contacts': [],
                },
                headers={'Authorization': f'Bearer {self.access_token}'},
                timeout=5
            )
            self.assertEqual(response.status_code, 201)
            result = response.json()
            self.assertIn('id', result)

            incidents = requests.get(
                f"{self.base_url}/api/v1/incidents/",
                headers={'Authorization': f'Bearer {self.access_token}'},
                timeout=5,
            )
            self.assertEqual(incidents.status_code, 200)
            self.assertTrue(any(item.get('id') == result['id'] for item in incidents.json()))
        except requests.RequestException:
            self.skipTest("API Gateway not running")


if __name__ == '__main__':
    unittest.main()
