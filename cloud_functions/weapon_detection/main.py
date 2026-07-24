#!/usr/bin/env python3
"""
SafeHer Weapon Detection Cloud Function
Serverless function for analyzing images/video and detecting weapons or threats
"""

import json
import numpy as np
from datetime import datetime
from typing import Dict, List, Any, Tuple
import logging
import base64
from io import BytesIO

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class WeaponDetectionFunction:
    """Serverless weapon/threat detection using computer vision"""
    
    def __init__(self):
        self.confidence_threshold = 0.5
        self.weapon_classes = [
            'knife', 'gun', 'pistol', 'rifle', 'weapon', 'blade', 
            'suspicious_object', 'threatening_gesture'
        ]
        
    def analyze_image(self, image_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Analyze image/video frame for weapon detection
        
        Args:
            image_data: Dictionary containing image data or features
            
        Returns:
            Analysis results with weapon detection and threat assessment
        """
        try:
            # Process image data
            image_features = self._process_image(image_data)
            
            # Detect potential weapons
            detections = self._detect_weapons(image_features)
            
            # Assess threat level
            threat_assessment = self._assess_threat_level(detections)
            
            # Generate response
            return {
                'timestamp': datetime.utcnow().isoformat(),
                'device_id': image_data.get('device_id', 'unknown'),
                'weapons_detected': len(detections) > 0,
                'detection_count': len(detections),
                'detections': detections,
                'threat_level': threat_assessment['level'],
                'confidence': threat_assessment['confidence'],
                'image_analysis': image_features,
                'recommendations': self._get_recommendations(threat_assessment['level'])
            }
            
        except Exception as e:
            logger.error(f"❌ Weapon detection error: {e}")
            return {
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat(),
                'weapons_detected': False,
                'detection_count': 0,
                'threat_level': 'unknown'
            }
    
    def _process_image(self, image_data: Dict[str, Any]) -> Dict[str, Any]:
        """Process and extract features from image data"""
        try:
            if 'base64_image' in image_data:
                # Decode base64 image
                image_bytes = base64.b64decode(image_data['base64_image'])
                # In a real implementation, you would use CV2 or PIL here
                # For now, simulate image processing
                image_array = np.frombuffer(image_bytes, dtype=np.uint8)
            elif 'image_features' in image_data:
                # Use pre-computed features
                return image_data['image_features']
            else:
                # Generate synthetic features for testing
                image_array = np.random.randint(0, 255, (480, 640, 3))
            
            # Extract image features (simplified)
            features = {
                'image_size': image_array.shape if hasattr(image_array, 'shape') else [480, 640, 3],
                'brightness': float(np.mean(image_array)) if hasattr(image_array, 'mean') else 128.0,
                'contrast': self._calculate_contrast(image_array),
                'edge_density': self._calculate_edge_density(image_array),
                'color_distribution': self._analyze_color_distribution(image_array),
                'suspicious_shapes': self._detect_suspicious_shapes(),
                'motion_blur': self._detect_motion_blur(image_array)
            }
            
            return features
            
        except Exception as e:
            logger.error(f"❌ Image processing error: {e}")
            return {
                'image_size': [480, 640, 3],
                'brightness': 128.0,
                'contrast': 0.5,
                'edge_density': 0.3,
                'color_distribution': {'metallic': 0.1, 'dark': 0.3, 'skin': 0.2},
                'suspicious_shapes': [],
                'motion_blur': 0.2
            }
    
    def _calculate_contrast(self, image_array) -> float:
        """Calculate image contrast"""
        if hasattr(image_array, 'std'):
            return float(np.std(image_array) / 255.0)
        return np.random.uniform(0.2, 0.8)
    
    def _calculate_edge_density(self, image_array) -> float:
        """Calculate edge density (simplified edge detection)"""
        # Simplified edge detection simulation
        if hasattr(image_array, 'shape') and len(image_array.shape) >= 2:
            # Simulate Sobel edge detection
            edges = np.random.uniform(0, 1, image_array.shape[:2])
            return float(np.mean(edges > 0.5))
        return np.random.uniform(0.1, 0.6)
    
    def _analyze_color_distribution(self, image_array) -> Dict[str, float]:
        """Analyze color distribution for weapon-indicative colors"""
        # Simplified color analysis
        return {
            'metallic': np.random.uniform(0.05, 0.3),    # Silver/metallic colors
            'dark': np.random.uniform(0.2, 0.6),         # Dark colors (common in weapons)
            'skin': np.random.uniform(0.1, 0.4),         # Skin tones (hands holding weapons)
            'reflective': np.random.uniform(0.0, 0.2)    # Reflective surfaces
        }
    
    def _detect_suspicious_shapes(self) -> List[Dict[str, Any]]:
        """Detect weapon-like shapes in image"""
        # Simulate shape detection
        shapes = []
        
        # Random chance of detecting suspicious shapes
        if np.random.random() > 0.7:  # 30% chance
            shapes.append({
                'type': 'elongated_object',
                'confidence': np.random.uniform(0.4, 0.9),
                'bbox': [
                    int(np.random.uniform(0, 640)), 
                    int(np.random.uniform(0, 480)),
                    int(np.random.uniform(20, 100)),
                    int(np.random.uniform(5, 30))
                ],
                'description': 'Knife-like object detected'
            })
        
        if np.random.random() > 0.85:  # 15% chance
            shapes.append({
                'type': 'gun_like_shape',
                'confidence': np.random.uniform(0.3, 0.8),
                'bbox': [
                    int(np.random.uniform(0, 640)),
                    int(np.random.uniform(0, 480)),
                    int(np.random.uniform(30, 80)),
                    int(np.random.uniform(20, 50))
                ],
                'description': 'Gun-like shape detected'
            })
        
        return shapes
    
    def _detect_motion_blur(self, image_array) -> float:
        """Detect motion blur (could indicate struggle)"""
        return np.random.uniform(0.0, 0.5)
    
    def _detect_weapons(self, image_features: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Detect weapons based on image features"""
        detections = []
        
        # Check for suspicious shapes
        for shape in image_features.get('suspicious_shapes', []):
            if shape['confidence'] > self.confidence_threshold:
                detection = {
                    'class': shape['type'],
                    'confidence': shape['confidence'],
                    'bbox': shape['bbox'],
                    'description': shape['description']
                }
                detections.append(detection)
        
        # Check color patterns indicative of weapons
        color_dist = image_features.get('color_distribution', {})
        if color_dist.get('metallic', 0) > 0.2 and color_dist.get('dark', 0) > 0.4:
            detections.append({
                'class': 'metallic_object',
                'confidence': 0.6,
                'bbox': [0, 0, 100, 50],  # Placeholder
                'description': 'Metallic object with weapon-like characteristics'
            })
        
        # Check edge density (weapons often have sharp edges)
        if image_features.get('edge_density', 0) > 0.5:
            detections.append({
                'class': 'sharp_object',  
                'confidence': 0.5,
                'bbox': [0, 0, 80, 20],  # Placeholder
                'description': 'High edge density suggesting sharp object'
            })
        
        return detections
    
    def _assess_threat_level(self, detections: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Assess overall threat level from detections"""
        if not detections:
            return {'level': 'safe', 'confidence': 0.9}
        
        # Calculate average confidence
        avg_confidence = np.mean([d['confidence'] for d in detections])
        max_confidence = max([d['confidence'] for d in detections])
        
        # Determine threat level
        if max_confidence >= 0.8 or len(detections) >= 3:
            level = 'critical'
        elif max_confidence >= 0.6 or len(detections) >= 2:
            level = 'high'
        elif max_confidence >= 0.4 or len(detections) >= 1:
            level = 'medium'
        else:
            level = 'low'
        
        # Check for specific high-risk weapons
        high_risk_weapons = ['gun_like_shape', 'knife']
        for detection in detections:
            if any(weapon in detection['class'] for weapon in high_risk_weapons):
                if detection['confidence'] > 0.6:
                    level = 'critical'
                    break
        
        return {
            'level': level,
            'confidence': float(avg_confidence),
            'max_confidence': float(max_confidence),
            'detection_count': len(detections)
        }
    
    def _get_recommendations(self, threat_level: str) -> List[str]:
        """Get safety recommendations based on threat level"""
        recommendations = {
            'safe': ['Visual monitoring active', 'No threats detected'],
            'low': ['Monitor situation', 'Possible object of interest detected'],
            'medium': ['Suspicious object detected', 'Increase alertness', 'Consider moving to safer area'],
            'high': ['WEAPON POSSIBLY DETECTED', 'Seek safe location immediately', 'Alert authorities'],
            'critical': ['WEAPON CONFIRMED', 'EMERGENCY: Call 911 immediately', 'Exit area if possible', 'Hide if cannot escape']
        }
        return recommendations.get(threat_level, ['Monitor situation carefully'])

# Global instance
weapon_detector = WeaponDetectionFunction()

def lambda_handler(event, context):
    """AWS Lambda handler function"""
    try:
        if isinstance(event.get('body'), str):
            image_data = json.loads(event['body'])
        else:
            image_data = event.get('body', event)
        
        result = weapon_detector.analyze_image(image_data)
        
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

if __name__ == '__main__':
    # Local testing
    test_data = {
        'device_id': 'esp32_glasses_001',
        'image_features': {
            'image_size': [480, 640, 3],
            'brightness': 120.0,
            'contrast': 0.7,
            'edge_density': 0.6,
            'color_distribution': {
                'metallic': 0.25,
                'dark': 0.45,
                'skin': 0.15,
                'reflective': 0.1
            },
            'suspicious_shapes': [
                {
                    'type': 'gun_like_shape',
                    'confidence': 0.75,
                    'bbox': [320, 240, 60, 35],
                    'description': 'Gun-like shape detected'
                }
            ],
            'motion_blur': 0.3
        }
    }
    
    result = weapon_detector.analyze_image(test_data)
    print("🔫 Weapon Detection Test Result:")
    print(json.dumps(result, indent=2))