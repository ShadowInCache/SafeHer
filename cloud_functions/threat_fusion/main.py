#!/usr/bin/env python3
"""
SafeHer Threat Fusion Cloud Function
Serverless function for correlating multiple threat indicators and generating unified threat assessment
"""

import json
import numpy as np
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ThreatFusionFunction:
    """Serverless threat fusion and correlation engine"""
    
    def __init__(self):
        self.threat_weights = {
            'motion': 0.35,      # Motion sensor importance
            'voice': 0.30,       # Voice analysis importance  
            'weapon': 0.35       # Weapon detection importance
        }
        
        self.fusion_rules = {
            'critical': {
                'min_sources': 2,
                'min_score': 0.8,
                'weapon_override': True  # Weapon detection can trigger critical alone
            },
            'high': {
                'min_sources': 1,
                'min_score': 0.6,
                'multi_source_boost': 0.2
            },
            'medium': {
                'min_sources': 1,
                'min_score': 0.4
            }
        }
        
    def fuse_threats(self, threat_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Fuse multiple threat indicators into unified assessment
        
        Args:
            threat_data: Dictionary containing threat analysis from multiple sources
            
        Returns:
            Unified threat assessment with correlation analysis
        """
        try:
            # Extract individual threat analyses
            threats = self._extract_threat_analyses(threat_data)
            
            # Calculate correlation scores  
            correlation = self._calculate_correlation(threats)
            
            # Apply fusion rules
            unified_assessment = self._apply_fusion_rules(threats, correlation)
            
            # Generate emergency response plan
            response_plan = self._generate_response_plan(unified_assessment)
            
            # Compile final result
            return {
                'timestamp': datetime.utcnow().isoformat(),
                'device_id': threat_data.get('device_id', 'unknown'),
                'user_id': threat_data.get('user_id', 'unknown'),
                'fusion_result': unified_assessment,
                'individual_threats': threats,
                'correlation_analysis': correlation,
                'response_plan': response_plan,
                'confidence': unified_assessment['confidence'],
                'threat_level': unified_assessment['level'],
                'recommendations': self._get_recommendations(unified_assessment['level'])
            }
            
        except Exception as e:
            logger.error(f"❌ Threat fusion error: {e}")
            return {
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat(),
                'fusion_result': {'level': 'unknown', 'confidence': 0.0},
                'threat_level': 'unknown'
            }
    
    def _extract_threat_analyses(self, threat_data: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
        """Extract and normalize individual threat analyses"""
        threats = {}
        
        # Motion analysis
        if 'motion_analysis' in threat_data:
            motion = threat_data['motion_analysis']
            threats['motion'] = {
                'detected': motion.get('threat_detected', False),
                'confidence': motion.get('confidence', 0.0),
                'level': motion.get('threat_level', 'safe'),
                'features': motion.get('features', {}),
                'timestamp': motion.get('timestamp', datetime.utcnow().isoformat())
            }
        
        # Voice analysis
        if 'voice_analysis' in threat_data:
            voice = threat_data['voice_analysis']
            threats['voice'] = {
                'detected': voice.get('distress_detected', False),
                'confidence': voice.get('distress_score', 0.0),
                'level': voice.get('threat_level', 'safe'),
                'indicators': voice.get('threat_indicators', []),
                'timestamp': voice.get('timestamp', datetime.utcnow().isoformat())
            }
        
        # Weapon detection
        if 'weapon_analysis' in threat_data:
            weapon = threat_data['weapon_analysis']
            threats['weapon'] = {
                'detected': weapon.get('weapons_detected', False),
                'confidence': weapon.get('confidence', 0.0),
                'level': weapon.get('threat_level', 'safe'),
                'detections': weapon.get('detections', []),
                'timestamp': weapon.get('timestamp', datetime.utcnow().isoformat())
            }
        
        return threats
    
    def _calculate_correlation(self, threats: Dict[str, Dict[str, Any]]) -> Dict[str, Any]:
        """Calculate correlation between different threat indicators"""
        correlation = {
            'temporal_correlation': 0.0,
            'severity_correlation': 0.0,
            'confidence_correlation': 0.0,
            'pattern_matches': [],
            'active_sources': len(threats)
        }
        
        if len(threats) < 2:
            return correlation
        
        # Calculate temporal correlation (how close in time are the detections)
        timestamps = []
        for threat_type, data in threats.items():
            if data['detected']:
                try:
                    ts = datetime.fromisoformat(data['timestamp'].replace('Z', '+00:00'))
                    timestamps.append(ts)
                except ValueError as e:
                    logger.warning(f"Invalid timestamp format: {str(e)}")
                    timestamps.append(datetime.utcnow())
        
        if len(timestamps) >= 2:
            time_diffs = []
            for i in range(len(timestamps)-1):
                diff = abs((timestamps[i] - timestamps[i+1]).total_seconds())
                time_diffs.append(diff)
            
            # Higher correlation if events are closer in time
            avg_diff = np.mean(time_diffs)
            correlation['temporal_correlation'] = max(0.0, 1.0 - avg_diff / 300.0)  # 5 min window
        
        # Calculate severity correlation
        levels = [data['level'] for data in threats.values() if data['detected']]
        if levels:
            level_scores = {'safe': 0, 'low': 1, 'medium': 2, 'high': 3, 'critical': 4}
            scores = [level_scores.get(level, 0) for level in levels]
            # Higher correlation if threat levels are similar
            if len(scores) > 1:
                correlation['severity_correlation'] = 1.0 - (np.std(scores) / 4.0)
            else:
                correlation['severity_correlation'] = 1.0
        
        # Calculate confidence correlation
        confidences = [data['confidence'] for data in threats.values() if data['detected']]
        if len(confidences) >= 2:
            # Higher correlation if confidences are similar and high
            correlation['confidence_correlation'] = np.mean(confidences) * (1.0 - np.std(confidences))
        
        # Identify pattern matches
        correlation['pattern_matches'] = self._identify_patterns(threats)
        
        return correlation
    
    def _identify_patterns(self, threats: Dict[str, Dict[str, Any]]) -> List[str]:
        """Identify common threat patterns"""
        patterns = []
        
        # Check for assault pattern (motion + voice)
        if ('motion' in threats and threats['motion']['detected'] and 
            'voice' in threats and threats['voice']['detected']):
            if (threats['motion']['level'] in ['high', 'critical'] and
                threats['voice']['level'] in ['high', 'critical']):
                patterns.append('physical_assault_pattern')
        
        # Check for armed threat pattern (weapon + motion)
        if ('weapon' in threats and threats['weapon']['detected'] and
            'motion' in threats and threats['motion']['detected']):
            patterns.append('armed_threat_pattern')
        
        # Check for abduction pattern (motion + sudden voice silence)
        if ('motion' in threats and threats['motion']['detected'] and
            'voice' in threats):
            voice_indicators = threats['voice'].get('indicators', [])
            if 'sudden_silence' in voice_indicators:
                patterns.append('possible_abduction_pattern')
        
        # Check for distress pattern (high voice distress + weapon detection)
        if ('voice' in threats and 'weapon' in threats):
            if (threats['voice'].get('confidence', 0) > 0.7 and
                threats['weapon']['detected']):
                patterns.append('weapon_threatening_pattern')
        
        # Check for panic pattern (multiple high-confidence detections)
        high_conf_threats = [t for t in threats.values() 
                           if t['detected'] and t['confidence'] > 0.7]
        if len(high_conf_threats) >= 2:
            patterns.append('multi_source_panic_pattern')
        
        return patterns
    
    def _apply_fusion_rules(self, threats: Dict[str, Dict[str, Any]], 
                          correlation: Dict[str, Any]) -> Dict[str, Any]:
        """Apply fusion rules to determine unified threat level"""
        
        # Calculate weighted threat score
        total_score = 0.0
        active_sources = 0
        
        for threat_type, data in threats.items():
            if data['detected']:
                weight = self.threat_weights.get(threat_type, 0.33)
                confidence = data['confidence']
                level_multiplier = {
                    'safe': 0.0, 'low': 0.25, 'medium': 0.5, 
                    'high': 0.75, 'critical': 1.0
                }.get(data['level'], 0.0)
                
                score = weight * confidence * level_multiplier
                total_score += score
                active_sources += 1
        
        # Apply correlation boost
        if correlation['active_sources'] > 1:
            correlation_boost = (
                correlation['temporal_correlation'] * 0.1 +
                correlation['severity_correlation'] * 0.1 +
                correlation['confidence_correlation'] * 0.1
            )
            total_score += correlation_boost
        
        # Apply pattern boosts
        pattern_boost = len(correlation['pattern_matches']) * 0.05
        total_score += pattern_boost
        
        # Weapon detection override
        weapon_threat = threats.get('weapon', {})
        if (weapon_threat.get('detected', False) and 
            weapon_threat.get('confidence', 0) > 0.6):
            total_score = max(total_score, 0.8)  # Force high threat level
        
        # Determine final threat level
        if total_score >= 0.8:
            level = 'critical'
        elif total_score >= 0.6:
            level = 'high'
        elif total_score >= 0.4:
            level = 'medium'
        elif total_score >= 0.2:
            level = 'low'
        else:
            level = 'safe'
        
        # Override based on fusion rules
        for rule_level, rules in self.fusion_rules.items():
            if active_sources >= rules.get('min_sources', 1):
                if total_score >= rules.get('min_score', 0):
                    if rule_level == 'critical' and rules.get('weapon_override', False):
                        if weapon_threat.get('detected', False):
                            level = 'critical'
                            break
        
        return {
            'level': level,
            'confidence': min(total_score, 1.0),
            'raw_score': total_score,
            'active_sources': active_sources,
            'correlation_score': (
                correlation['temporal_correlation'] + 
                correlation['severity_correlation'] + 
                correlation['confidence_correlation']
            ) / 3.0
        }
    
    def _generate_response_plan(self, assessment: Dict[str, Any]) -> Dict[str, Any]:
        """Generate emergency response plan based on threat level"""
        level = assessment['level']
        
        response_plans = {
            'safe': {
                'priority': 'low',
                'actions': ['Continue monitoring', 'Maintain normal operations'],
                'notifications': [],
                'escalation_timer': None
            },
            'low': {
                'priority': 'low',
                'actions': ['Increase monitoring frequency', 'Log event for review'],
                'notifications': ['Log to system'],
                'escalation_timer': 300  # 5 minutes
            },
            'medium': {
                'priority': 'medium',
                'actions': ['Alert user', 'Notify emergency contacts', 'Increase sensor sensitivity'],
                'notifications': ['User notification', 'Emergency contacts SMS'],
                'escalation_timer': 180  # 3 minutes
            },
            'high': {
                'priority': 'high',
                'actions': ['Immediate user alert', 'Contact emergency services', 'Send location'],
                'notifications': ['User alert', 'Emergency contacts call', 'SMS to authorities'],
                'escalation_timer': 60   # 1 minute
            },
            'critical': {
                'priority': 'critical',
                'actions': ['EMERGENCY: Call 911', 'Send GPS location', 'Audio/video recording', 'Contact all emergency contacts'],
                'notifications': ['IMMEDIATE 911 call', 'Emergency broadcast', 'All contacts notification'],
                'escalation_timer': 0    # Immediate
            }
        }
        
        plan = response_plans.get(level, response_plans['medium'])
        
        # Add timestamp for escalation
        if plan['escalation_timer'] is not None:
            escalation_time = datetime.utcnow() + timedelta(seconds=plan['escalation_timer'])
            plan['escalation_time'] = escalation_time.isoformat()
        
        return plan
    
    def _get_recommendations(self, threat_level: str) -> List[str]:
        """Get comprehensive safety recommendations"""
        recommendations = {
            'safe': [
                'SafeHer system monitoring normally',
                'All threat indicators at safe levels',
                'Continue with planned activities'
            ],
            'low': [
                'Mild threat indicators detected',
                'Stay aware of surroundings',
                'Keep SafeHer device active',
                'Consider moving to busier area if alone'
            ],
            'medium': [
                'Multiple threat indicators active',
                'Move to safer location if possible',
                'Alert trusted contacts of situation', 
                'Stay in well-lit, populated areas',
                'Prepare to call for help'
            ],
            'high': [
                'HIGH THREAT DETECTED',
                'Seek immediate help from others',
                'Move to public area with witnesses',
                'Call emergency contacts now',
                'Prepare to contact authorities',
                'Trust your instincts - leave if unsafe'
            ],
            'critical': [
                'CRITICAL EMERGENCY DETECTED',
                '🚨 CALL 911 IMMEDIATELY 🚨',
                'Run to safety if possible',
                'Scream for help to attract attention',
                'Fight back only if cornered',
                'Emergency services are being contacted'
            ]
        }
        
        return recommendations.get(threat_level, recommendations['medium'])

# Global instance
threat_fusion = ThreatFusionFunction()

def lambda_handler(event, context):
    """AWS Lambda handler function"""
    try:
        if isinstance(event.get('body'), str):
            threat_data = json.loads(event['body'])
        else:
            threat_data = event.get('body', event)
        
        result = threat_fusion.fuse_threats(threat_data)
        
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
        'device_id': 'esp32_device_001',
        'user_id': 'user_12345',
        'motion_analysis': {
            'threat_detected': True,
            'confidence': 0.85,
            'threat_level': 'high',
            'features': {'magnitude': 25.3},
            'timestamp': datetime.utcnow().isoformat()
        },
        'voice_analysis': {
            'distress_detected': True,
            'distress_score': 0.75,
            'threat_level': 'high',
            'threat_indicators': ['shouting_detected', 'distressed_speech'],
            'timestamp': datetime.utcnow().isoformat()
        },
        'weapon_analysis': {
            'weapons_detected': True,
            'confidence': 0.7,
            'threat_level': 'critical',
            'detections': [{'class': 'knife', 'confidence': 0.7}],
            'timestamp': datetime.utcnow().isoformat()
        }
    }
    
    result = threat_fusion.fuse_threats(test_data)
    print("🔀 Threat Fusion Test Result:")
    print(json.dumps(result, indent=2))