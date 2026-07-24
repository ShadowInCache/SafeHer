#!/usr/bin/env python3
"""
SafeHer Motion Detection Cloud Function
Serverless function for analyzing motion sensor data and detecting threats
"""

import json
import numpy as np
import xgboost as xgb
from datetime import datetime
from typing import Dict, List, Any
import os
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class MotionDetectionFunction:
    """Serverless motion detection using XGBoost"""
    
    def __init__(self):
        self.model = None
        self.load_model()
    
    def load_model(self):
        """Load the trained XGBoost model"""
        try:
            model_path = os.path.join(os.path.dirname(__file__), 'models', 'xgboost_motion_model.json')
            if os.path.exists(model_path):
                self.model = xgb.XGBClassifier()
                self.model.load_model(model_path)
                logger.info("✅ XGBoost motion model loaded successfully")
            else:
                logger.warning("⚠️ Model file not found, using synthetic model")
                self._create_synthetic_model()
        except Exception as e:
            logger.error(f"❌ Error loading model: {e}")
            self._create_synthetic_model()
    
    def _create_synthetic_model(self):
        """Create a synthetic model for testing"""
        self.model = xgb.XGBClassifier(
            n_estimators=100,
            max_depth=6,
            learning_rate=0.1,
            subsample=0.8,
            colsample_bytree=0.8,
            random_state=42
        )
        
        # Generate synthetic training data
        X_synthetic = np.random.randn(1000, 7)
        # Create threat labels based on magnitude
        y_synthetic = (np.abs(X_synthetic).sum(axis=1) > 5).astype(int)
        
        self.model.fit(X_synthetic, y_synthetic)
        logger.info("✅ Synthetic XGBoost model created")
    
    def analyze_motion(self, motion_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Analyze motion sensor data for threats
        
        Args:
            motion_data: Dictionary containing motion sensor readings
            
        Returns:
            Analysis results with threat level and confidence
        """
        try:
            # Extract motion features
            features = self._extract_features(motion_data)
            
            # Make prediction
            prediction = self.model.predict([features])[0]
            confidence = max(self.model.predict_proba([features])[0])
            
            # Determine threat level
            threat_level = self._calculate_threat_level(prediction, confidence)
            
            return {
                'timestamp': datetime.utcnow().isoformat(),
                'device_id': motion_data.get('device_id', 'unknown'),
                'threat_detected': bool(prediction),
                'confidence': float(confidence),
                'threat_level': threat_level,
                'features': {
                    'acceleration_x': features[0],
                    'acceleration_y': features[1], 
                    'acceleration_z': features[2],
                    'gyroscope_x': features[3],
                    'gyroscope_y': features[4],
                    'gyroscope_z': features[5],
                    'magnitude': features[6]
                },
                'recommendations': self._get_recommendations(threat_level)
            }
            
        except Exception as e:
            logger.error(f"❌ Motion analysis error: {e}")
            return {
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat(),
                'threat_detected': False,
                'confidence': 0.0,
                'threat_level': 'unknown'
            }
    
    def _extract_features(self, motion_data: Dict[str, Any]) -> List[float]:
        """Extract features from motion sensor data"""
        # Default values if data is missing
        accel_x = motion_data.get('acceleration_x', 0.0)
        accel_y = motion_data.get('acceleration_y', 0.0) 
        accel_z = motion_data.get('acceleration_z', 9.8)  # Default gravity
        gyro_x = motion_data.get('gyroscope_x', 0.0)
        gyro_y = motion_data.get('gyroscope_y', 0.0)
        gyro_z = motion_data.get('gyroscope_z', 0.0)
        
        # Calculate magnitude
        magnitude = np.sqrt(accel_x**2 + accel_y**2 + accel_z**2)
        
        return [accel_x, accel_y, accel_z, gyro_x, gyro_y, gyro_z, magnitude]
    
    def _calculate_threat_level(self, prediction: int, confidence: float) -> str:
        """Calculate threat level based on prediction and confidence"""
        if not prediction:
            return 'safe'
        elif confidence >= 0.9:
            return 'critical'
        elif confidence >= 0.7:
            return 'high'
        elif confidence >= 0.5:
            return 'medium'
        else:
            return 'low'
    
    def _get_recommendations(self, threat_level: str) -> List[str]:
        """Get safety recommendations based on threat level"""
        recommendations = {
            'safe': ['Continue normal activities', 'Device monitoring active'],
            'low': ['Stay alert', 'Keep device active', 'Check surroundings'],
            'medium': ['Move to safer location', 'Alert emergency contacts', 'Call for help if needed'],
            'high': ['Seek immediate help', 'Contact emergency services', 'Move to public area'],
            'critical': ['EMERGENCY: Call 911 immediately', 'Activate panic mode', 'Send location to emergency contacts']
        }
        return recommendations.get(threat_level, ['Monitor situation carefully'])

# Global instance
motion_detector = MotionDetectionFunction()

def lambda_handler(event, context):
    """AWS Lambda handler function"""
    try:
        # Parse input data
        if isinstance(event.get('body'), str):
            motion_data = json.loads(event['body'])
        else:
            motion_data = event.get('body', event)
        
        # Analyze motion
        result = motion_detector.analyze_motion(motion_data)
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(result)
        }
        
    except Exception as e:
        logger.error(f"❌ Lambda handler error: {e}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': f'Internal server error: {str(e)}',
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def gcp_handler(request):
    """Google Cloud Function handler"""
    try:
        motion_data = request.get_json()
        result = motion_detector.analyze_motion(motion_data)
        return result
    except Exception as e:
        return {'error': str(e)}, 500

def azure_handler(req):
    """Azure Function handler"""
    try:
        motion_data = req.get_json()
        result = motion_detector.analyze_motion(motion_data)
        return result
    except Exception as e:
        return {'error': str(e)}, 500

if __name__ == '__main__':
    # Local testing
    test_data = {
        'device_id': 'esp32_glove_001',
        'acceleration_x': 15.2,
        'acceleration_y': -8.5,
        'acceleration_z': 12.1,
        'gyroscope_x': 3.2,
        'gyroscope_y': -1.8,
        'gyroscope_z': 4.5
    }
    
    result = motion_detector.analyze_motion(test_data)
    print("🧪 Motion Detection Test Result:")
    print(json.dumps(result, indent=2))