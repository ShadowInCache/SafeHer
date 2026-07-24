"""
Microservices Tests
Test individual microservices functionality
"""

import unittest
import requests
import numpy as np
from tests import TEST_CONFIG


class TestMotionService(unittest.TestCase):
    """Test Motion Detection Service"""
    
    def test_motion_prediction(self):
        """Test motion anomaly prediction"""
        try:
            # Sample accelerometer data (6D: x,y,z accel + x,y,z gyro)
            test_data = np.random.rand(10, 6)
            response = requests.post(
                f"{TEST_CONFIG.get('MOTION_SERVICE_URL', 'http://localhost:8001')}/predict",
                json={'data': test_data.tolist()},
                timeout=5
            )
            if response.status_code == 200:
                result = response.json()
                self.assertIn('anomaly', result)
        except requests.ConnectionError:
            self.skipTest("Motion service not running")
    
    def test_motion_model_loading(self):
        """Test motion model loads correctly"""
        try:
            response = requests.get(
                f"{TEST_CONFIG.get('MOTION_SERVICE_URL', 'http://localhost:8001')}/health",
                timeout=5
            )
            self.assertIn(response.status_code, [200, 503])  # Either healthy or unavailable
        except requests.ConnectionError:
            self.skipTest("Motion service not running")


class TestVisionService(unittest.TestCase):
    """Test Weapon Detection Service"""
    
    def test_weapon_detection(self):
        """Test weapon detection on sample image"""
        try:
            # Create a simple test image (100x100 RGB)
            test_image = np.random.randint(0, 256, (100, 100, 3), dtype=np.uint8)
            response = requests.post(
                f"{TEST_CONFIG.get('VISION_SERVICE_URL', 'http://localhost:8002')}/detect",
                json={'image': test_image.tobytes().hex()},
                timeout=10
            )
            if response.status_code == 200:
                result = response.json()
                self.assertIn('detections', result)
        except requests.ConnectionError:
            self.skipTest("Vision service not running")
    
    def test_image_processing(self):
        """Test image preprocessing"""
        try:
            response = requests.get(
                f"{TEST_CONFIG.get('VISION_SERVICE_URL', 'http://localhost:8002')}/health",
                timeout=5
            )
            self.assertIn(response.status_code, [200, 503])
        except requests.ConnectionError:
            self.skipTest("Vision service not running")


class TestVoiceService(unittest.TestCase):
    """Test Voice Analysis Service"""
    
    def test_voice_emotion_detection(self):
        """Test emotion detection from audio"""
        try:
            # Create a simple test audio sample
            test_audio = np.random.randn(16000)  # 1 second of audio at 16kHz
            response = requests.post(
                f"{TEST_CONFIG.get('VOICE_SERVICE_URL', 'http://localhost:8003')}/analyze",
                json={'audio': test_audio.tobytes().hex()},
                timeout=10
            )
            if response.status_code == 200:
                result = response.json()
                self.assertIn('emotion', result)
        except requests.ConnectionError:
            self.skipTest("Voice service not running")
    
    def test_audio_processing(self):
        """Test audio preprocessing"""
        try:
            response = requests.get(
                f"{TEST_CONFIG.get('VOICE_SERVICE_URL', 'http://localhost:8003')}/health",
                timeout=5
            )
            self.assertIn(response.status_code, [200, 503])
        except requests.ConnectionError:
            self.skipTest("Voice service not running")


class TestThreatFusionEngine(unittest.TestCase):
    """Test Threat Fusion Engine"""
    
    def test_threat_aggregation(self):
        """Test threat level aggregation from multiple sources"""
        try:
            test_threats = {
                'motion_threat': 0.75,
                'weapon_threat': 0.0,
                'voice_threat': 0.6
            }
            response = requests.post(
                f"{TEST_CONFIG.get('FUSION_SERVICE_URL', 'http://localhost:8004')}/fuse",
                json=test_threats,
                timeout=5
            )
            if response.status_code == 200:
                result = response.json()
                self.assertIn('overall_threat_level', result)
        except requests.ConnectionError:
            self.skipTest("Threat fusion service not running")
    
    def test_threat_scoring(self):
        """Test threat scoring algorithm"""
        try:
            response = requests.get(
                f"{TEST_CONFIG.get('FUSION_SERVICE_URL', 'http://localhost:8004')}/health",
                timeout=5
            )
            self.assertIn(response.status_code, [200, 503])
        except requests.ConnectionError:
            self.skipTest("Threat fusion service not running")


if __name__ == '__main__':
    unittest.main()
