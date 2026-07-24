/// Model for real-time threat level updates from the Threat Fusion Engine
class ThreatUpdate {
  final String userId;
  final String threatId;
  final double threatScore;
  final String threatLevel; // 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL'
  final Map<String, dynamic> indicators;
  final Map<String, dynamic> location;
  final DateTime timestamp;
  final String source;
  final Map<String, dynamic>? metadata;

  const ThreatUpdate({
    required this.userId,
    required this.threatId,
    required this.threatScore,
    required this.threatLevel,
    required this.indicators,
    required this.location,
    required this.timestamp,
    required this.source,
    this.metadata,
  });

  factory ThreatUpdate.fromJson(Map<String, dynamic> json) {
    return ThreatUpdate(
      userId: json['user_id'] ?? '',
      threatId: json['threat_id'] ?? '',
      threatScore: (json['threat_score'] ?? 0.0).toDouble(),
      threatLevel: json['threat_level'] ?? 'LOW',
      indicators: json['indicators'] ?? {},
      location: json['location'] ?? {},
      timestamp:
          DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      source: json['source'] ?? 'unknown',
      metadata: json['metadata'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'threat_id': threatId,
      'threat_score': threatScore,
      'threat_level': threatLevel,
      'indicators': indicators,
      'location': location,
      'timestamp': timestamp.toIso8601String(),
      'source': source,
      if (metadata != null) 'metadata': metadata,
    };
  }

  /// Check if this is a critical threat requiring immediate action
  bool get isCritical => threatLevel == 'CRITICAL' || threatScore >= 0.9;

  /// Check if this is a high-priority threat
  bool get isHighPriority => threatLevel == 'HIGH' || threatScore >= 0.7;

  /// Get formatted threat description
  String get description {
    final List<String> activeIndicators = [];

    if (indicators['motion_threat'] == true) {
      activeIndicators.add('Motion Anomaly Detected');
    }
    if (indicators['weapon_detected'] == true) {
      activeIndicators.add('Weapon Detected');
    }
    if (indicators['voice_distress'] == true) {
      activeIndicators.add('Voice Distress');
    }
    if (indicators['gps_anomaly'] == true) {
      activeIndicators.add('Location Anomaly');
    }

    if (activeIndicators.isEmpty) {
      return 'Unknown threat detected';
    }

    return activeIndicators.join(', ');
  }

  @override
  String toString() {
    return 'ThreatUpdate(userId: $userId, threatLevel: $threatLevel, score: $threatScore, indicators: $description)';
  }
}
