#!/usr/bin/env python3
"""
SafeHer Voice Analysis Cloud Function  
Serverless function for analyzing audio data and detecting vocal distress
"""

import json
import numpy as np
from datetime import datetime
from typing import Dict, List, Any
import logging
import base64
import pickle
import os
from pathlib import Path

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class VoiceAnalysisFunction:
    """Serverless voice/audio threat detection"""
    
    def __init__(self):
        self.sample_rate = 16000
        self.chunk_duration = 2.0  # seconds
        self.model = None
        self.scaler = None
        self.load_model()
    
    def load_model(self):
        """Load trained voice detection model"""
        try:
            # Try multiple paths for model files
            possible_paths = [
                Path('../../src/models/voice_detection/voice_model.pkl'),
                Path('../../../src/models/voice_detection/voice_model.pkl'),
                Path('./src/models/voice_detection/voice_model.pkl'),
                Path('/app/src/models/voice_detection/voice_model.pkl'),
            ]
            
            model_path = None
            scaler_path = None
            
            for path in possible_paths:
                if path.exists():
                    model_path = path
                    scaler_path = path.parent / 'voice_scaler.pkl'
                    break
            
            if model_path and model_path.exists() and scaler_path.exists():
                with open(model_path, 'rb') as f:
                    self.model = pickle.load(f)
                with open(scaler_path, 'rb') as f:
                    self.scaler = pickle.load(f)
                logger.info("✅ Trained voice detection model loaded successfully")
            else:
                logger.warning("⚠️ Trained model not found, using heuristic analysis")
                self.model = None
                self.scaler = None
                
        except Exception as e:
            logger.warning(f"⚠️ Error loading model: {e}, using heuristic analysis")
            self.model = None
            self.scaler = None
        
    def analyze_voice(self, audio_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Analyze audio data for vocal distress indicators
        
        Args:
            audio_data: Dictionary containing audio samples or features
            
        Returns:
            Analysis results with threat detection and confidence
        """
        try:
            # Extract audio features
            features = self._extract_audio_features(audio_data)
            
            if self.model and self.scaler:
                # Use trained model for prediction
                distress_score, confidence = self._predict_with_model(features)
            else:
                # Use heuristic analysis as fallback
                distress_score = self._calculate_distress_score(features)
                confidence = distress_score
            
            # Detect specific threat patterns
            threat_indicators = self._detect_threat_patterns(features)
            
            # Calculate overall threat level
            threat_level = self._calculate_threat_level(distress_score, threat_indicators)
            
            return {
                'timestamp': datetime.utcnow().isoformat(),
                'device_id': audio_data.get('device_id', 'unknown'),
                'distress_detected': distress_score > 0.5,
                'distress_score': float(distress_score),
                'confidence': float(confidence),
                'threat_level': threat_level,
                'threat_indicators': threat_indicators,
                'audio_features': features,
                'model_used': 'trained_model' if self.model else 'heuristic_analysis',
                'recommendations': self._get_recommendations(threat_level)
            }
            
        except Exception as e:
            logger.error(f"❌ Voice analysis error: {e}")
            return {
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat(),
                'distress_detected': False,
                'distress_score': 0.0,
                'threat_level': 'unknown'
            }
    
    def _predict_with_model(self, features: Dict[str, float]) -> tuple:
        """Predict using trained model"""
        try:
            # Extract features in the correct order
            feature_order = [
                'rms_energy', 'zero_crossing_rate', 'spectral_centroid', 'spectral_rolloff',
                'mfcc_mean', 'mfcc_std', 'chroma_mean', 'chroma_std',
                'contrast_mean', 'contrast_std', 'onset_strength', 'spectral_flux'
            ]
            
            # Map simplified features to expected features
            feature_vector = []
            for feature_name in feature_order:
                if feature_name in features:
                    feature_vector.append(features[feature_name])
                else:
                    # Provide defaults
                    defaults = {
                        'rms_energy': features.get('rms_energy', 0.1),
                        'zero_crossing_rate': features.get('zero_crossing_rate', 0.05),
                        'spectral_centroid': features.get('spectral_centroid', 1500),
                        'spectral_rolloff': features.get('spectral_rolloff', 5000),
                        'mfcc_mean': -65.0,
                        'mfcc_std': 10.0,
                        'chroma_mean': 0.35,
                        'chroma_std': 0.15,
                        'contrast_mean': 3.0,
                        'contrast_std': 1.0,
                        'onset_strength': 0.03,
                        'spectral_flux': 0.2
                    }
                    feature_vector.append(defaults.get(feature_name, 0.0))
            
            # Normalize features
            X = np.array([feature_vector])
            X_scaled = self.scaler.transform(X)
            
            # Get prediction
            prediction = self.model.predict(X_scaled)[0]
            confidence = np.max(self.model.predict_proba(X_scaled)[0])
            
            # Convert prediction to distress score (0-1)
            distress_score = float(self.model.predict_proba(X_scaled)[0][1]) if prediction == 1 else confidence * 0.3
            
            return distress_score, confidence
            
        except Exception as e:
            logger.warning(f"⚠️ Model prediction failed: {e}, falling back to heuristic")
            distress_score = self._calculate_distress_score(features)
            return distress_score, distress_score
    
    def _extract_audio_features(self, audio_data: Dict[str, Any]) -> Dict[str, float]:
        """Extract features from audio data"""
        # Handle different input formats
        if 'raw_audio' in audio_data:
            # Decode base64 audio if provided
            audio_bytes = base64.b64decode(audio_data['raw_audio'])
            audio_samples = np.frombuffer(audio_bytes, dtype=np.float32)
        elif 'audio_features' in audio_data:
            # Use pre-computed features
            return audio_data['audio_features']
        else:
            # Generate synthetic features for testing
            audio_samples = np.random.randn(int(self.sample_rate * self.chunk_duration))
        
        # Extract key audio features
        features = {
            'rms_energy': float(np.sqrt(np.mean(audio_samples**2))),
            'zero_crossing_rate': self._calculate_zcr(audio_samples),
            'spectral_centroid': self._calculate_spectral_centroid(audio_samples),
            'pitch_variation': self._calculate_pitch_variation(audio_samples),
            'volume_level': float(np.max(np.abs(audio_samples))),
            'silence_ratio': self._calculate_silence_ratio(audio_samples),
            'frequency_peaks': len(self._find_frequency_peaks(audio_samples))
        }
        
        return features
    
    def _calculate_zcr(self, audio_samples: np.ndarray) -> float:
        """Calculate zero crossing rate"""
        zero_crossings = np.where(np.diff(np.sign(audio_samples)))[0]
        return len(zero_crossings) / len(audio_samples)
    
    def _calculate_spectral_centroid(self, audio_samples: np.ndarray) -> float:
        """Calculate spectral centroid (brightness)"""
        # Simplified spectral centroid calculation
        fft = np.abs(np.fft.fft(audio_samples))
        freqs = np.fft.fftfreq(len(audio_samples), 1/self.sample_rate)
        
        # Only positive frequencies
        fft = fft[:len(fft)//2]
        freqs = freqs[:len(freqs)//2]
        
        if np.sum(fft) > 0:
            centroid = np.sum(freqs * fft) / np.sum(fft)
            return float(centroid)
        return 0.0
    
    def _calculate_pitch_variation(self, audio_samples: np.ndarray) -> float:
        """Calculate pitch variation (indicates distress)"""
        # Simplified pitch variation using autocorrelation
        correlation = np.correlate(audio_samples, audio_samples, mode='full')
        correlation = correlation[correlation.size // 2:]
        
        # Find pitch periods
        peaks = []
        for i in range(1, min(len(correlation)-1, 800)):  # Up to ~50ms
            if correlation[i] > correlation[i-1] and correlation[i] > correlation[i+1]:
                if correlation[i] > 0.3 * np.max(correlation):
                    peaks.append(i)
        
        if len(peaks) > 1:
            pitch_periods = np.diff(peaks)
            return float(np.std(pitch_periods) / np.mean(pitch_periods)) if np.mean(pitch_periods) > 0 else 0.0
        return 0.0
    
    def _calculate_silence_ratio(self, audio_samples: np.ndarray) -> float:
        """Calculate ratio of silence in audio"""
        threshold = 0.01 * np.max(np.abs(audio_samples))
        silent_samples = np.sum(np.abs(audio_samples) < threshold)
        return silent_samples / len(audio_samples)
    
    def _find_frequency_peaks(self, audio_samples: np.ndarray) -> List[float]:
        """Find prominent frequency peaks"""
        fft = np.abs(np.fft.fft(audio_samples))
        fft = fft[:len(fft)//2]  # Only positive frequencies
        
        # Find peaks above threshold
        threshold = 0.1 * np.max(fft)
        peaks = []
        for i in range(1, len(fft)-1):
            if fft[i] > fft[i-1] and fft[i] > fft[i+1] and fft[i] > threshold:
                freq = i * self.sample_rate / len(audio_samples)
                peaks.append(freq)
        
        return peaks[:10]  # Return top 10 peaks
    
    def _calculate_distress_score(self, features: Dict[str, float]) -> float:
        """Calculate overall distress score from audio features"""
        score = 0.0
        
        # High energy often indicates shouting/distress
        if features['rms_energy'] > 0.5:
            score += 0.3
        elif features['rms_energy'] > 0.2:
            score += 0.1
        
        # High pitch variation indicates emotional distress
        if features['pitch_variation'] > 0.5:
            score += 0.4
        elif features['pitch_variation'] > 0.3:
            score += 0.2
        
        # Very high or very low volume can indicate distress
        volume = features['volume_level']
        if volume > 0.8 or volume < 0.1:
            score += 0.2
        
        # High zero crossing rate can indicate harsh/distressed speech
        if features['zero_crossing_rate'] > 0.15:
            score += 0.1
        
        return min(score, 1.0)  # Cap at 1.0
    
    def _detect_threat_patterns(self, features: Dict[str, float]) -> List[str]:
        """Detect specific threat patterns in audio"""
        indicators = []
        
        # Shouting/screaming pattern
        if features['rms_energy'] > 0.7 and features['pitch_variation'] > 0.4:
            indicators.append('shouting_detected')
        
        # Distressed speech pattern
        if features['pitch_variation'] > 0.5 and features['zero_crossing_rate'] > 0.12:
            indicators.append('distressed_speech')
        
        # Sudden silence (potential incapacitation)
        if features['silence_ratio'] > 0.8:
            indicators.append('sudden_silence')
        
        # High frequency content (possible whistle/alarm)
        frequency_peaks = features.get('frequency_peaks', [])
        if isinstance(frequency_peaks, (int, float)):
            # Handle case where frequency_peaks is a count instead of a list
            if frequency_peaks > 3:
                indicators.append('high_frequency_alarm')
        elif isinstance(frequency_peaks, list):
            high_freq_peaks = [f for f in frequency_peaks if isinstance(f, (int, float)) and f > 2000]
            if len(high_freq_peaks) > 3:
                indicators.append('high_frequency_alarm')
        
        # Irregular speech patterns
        if features['spectral_centroid'] > 2000 and features['pitch_variation'] > 0.3:
            indicators.append('irregular_speech')
        
        return indicators
    
    def _calculate_threat_level(self, distress_score: float, indicators: List[str]) -> str:
        """Calculate overall threat level"""
        if distress_score >= 0.8 or 'shouting_detected' in indicators:
            return 'critical'
        elif distress_score >= 0.6 or len(indicators) >= 3:
            return 'high'
        elif distress_score >= 0.4 or len(indicators) >= 2:
            return 'medium'
        elif distress_score >= 0.2 or len(indicators) >= 1:
            return 'low'
        else:
            return 'safe'
    
    def _get_recommendations(self, threat_level: str) -> List[str]:
        """Get safety recommendations based on threat level"""
        recommendations = {
            'safe': ['Audio monitoring active', 'Normal speech patterns detected'],
            'low': ['Monitor voice patterns', 'Check if user needs assistance'],
            'medium': ['Possible distress detected', 'Consider checking on user', 'Alert contacts if patterns persist'],
            'high': ['Distress indicators present', 'Contact user immediately', 'Alert emergency contacts'],
            'critical': ['AUDIO DISTRESS DETECTED', 'Contact emergency services immediately', 'Send location to responders']
        }
        return recommendations.get(threat_level, ['Monitor situation'])

# Global instance
voice_analyzer = VoiceAnalysisFunction()

def lambda_handler(event, context):
    """AWS Lambda handler function"""
    try:
        if isinstance(event.get('body'), str):
            audio_data = json.loads(event['body'])
        else:
            audio_data = event.get('body', event)
        
        result = voice_analyzer.analyze_voice(audio_data)
        
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
        'audio_features': {
            'rms_energy': 0.75,
            'zero_crossing_rate': 0.18,
            'spectral_centroid': 2100,
            'pitch_variation': 0.6,
            'volume_level': 0.85,
            'silence_ratio': 0.1,
            'frequency_peaks': 5
        }
    }
    
    result = voice_analyzer.analyze_voice(test_data)
    print("🎤 Voice Analysis Test Result:")
    print(json.dumps(result, indent=2))