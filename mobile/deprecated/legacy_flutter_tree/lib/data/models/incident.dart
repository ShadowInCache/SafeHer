// import 'package:cloud_firestore/cloud_firestore.dart'; // Disabled for web compatibility
import 'package:geolocator/geolocator.dart';

class Incident {
  final String id;
  final String userId;
  final DateTime timestamp;
  final Position location;
  final int threatLevel; // 0-4 (safe to critical)
  final List<String> alertTypes; // ['motion', 'weapon', 'voice', 'manual']
  final Map<String, dynamic> detectionData;
  final List<String> evidenceUrls; // images/videos/audio
  final IncidentStatus status;
  final List<String> notifiedContacts;
  final String? notes;

  Incident({
    required this.id,
    required this.userId,
    required this.timestamp,
    required this.location,
    required this.threatLevel,
    required this.alertTypes,
    required this.detectionData,
    required this.evidenceUrls,
    required this.status,
    required this.notifiedContacts,
    this.notes,
  });

  factory Incident.fromJson(Map<String, dynamic> json) {
    // Parse location from API response
    final locationData = json['location'] as Map<String, dynamic>?;
    
    return Incident(
      id: json['id']?.toString() ?? '',
      userId: json['userId'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      location: Position(
        latitude: locationData?['lat']?.toDouble() ?? 0.0,
        longitude: locationData?['lng']?.toDouble() ?? 0.0,
        timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      ),
      threatLevel: json['threatLevel'] as int? ?? 0,
      alertTypes: List<String>.from(json['alertTypes'] as List? ?? []),
      detectionData: json['detectionData'] as Map<String, dynamic>? ?? {},
      evidenceUrls: List<String>.from(json['evidenceUrls'] as List? ?? []),
      status: IncidentStatus.values.byName(json['status'] as String? ?? 'active'),
      notifiedContacts: List<String>.from(json['notifiedContacts'] as List? ?? []),
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'timestamp': timestamp.toIso8601String(),
      'location': {'lat': location.latitude, 'lng': location.longitude},
      'threatLevel': threatLevel,
      'alertTypes': alertTypes,
      'detectionData': detectionData,
      'evidenceUrls': evidenceUrls,
      'status': status.name,
      'notifiedContacts': notifiedContacts,
      'notes': notes,
    };
  }

  String get severityLabel {
    switch (threatLevel) {
      case 0:
        return 'Safe';
      case 1:
        return 'Low';
      case 2:
        return 'Medium';
      case 3:
        return 'High';
      case 4:
        return 'Critical';
      default:
        return 'Unknown';
    }
  }

  /// Calculate threat level from multi-modal risk scores
  /// Follows architecture flowchart: Risk Scoring Engine → Decision Logic
  static int calculateThreatLevel({
    double? motionRisk,
    double? weaponRisk,
    double? voiceRisk,
    int? stressLevel,
  }) {
    // Weighted multi-modal scoring (based on model accuracies)
    const double motionWeight = 0.30;  // 97.29% accuracy
    const double weaponWeight = 0.40;  // 84.85% mAP (most critical)
    const double voiceWeight = 0.30;   // 68.8% accuracy
    
    double totalRisk = ((motionRisk ?? 0.0) * motionWeight) +
                       ((weaponRisk ?? 0.0) * weaponWeight) +
                       ((voiceRisk ?? 0.0) * voiceWeight);
    
    // Stress level booster (if available)
    if (stressLevel != null && stressLevel > 70) {
      totalRisk += 0.1; // +10% for high stress
    }
    
    totalRisk = totalRisk.clamp(0.0, 1.0);
    
    // Decision thresholds (matches flowchart Compare with Threshold logic)
    if (totalRisk >= 0.8) return 4; // Critical - Danger State
    if (totalRisk >= 0.6) return 3; // High - Danger State
    if (totalRisk >= 0.4) return 2; // Medium - Warning State
    if (totalRisk >= 0.2) return 1; // Low - Warning State
    return 0; // Safe State
  }

  /// Determine which immediate responses should trigger
  /// Based on flowchart: Immediate Response (Activate Shock, Trigger Buzzer/Vibration)
  Map<String, bool> getImmediateResponseActions() {
    return {
      'activateShock': threatLevel >= 4,      // Critical only
      'triggerBuzzer': threatLevel >= 3,      // High and Critical
      'triggerVibration': threatLevel >= 3,   // High and Critical
      'sendAlert': threatLevel >= 2,          // Medium, High, Critical
      'captureEvidence': threatLevel >= 2,    // Medium, High, Critical
    };
  }
}

enum IncidentStatus {
  active,
  resolved,
  falseAlarm,
  underReview,
}

class EmergencyContact {
  final String id;
  final String name;
  final String phoneNumber;
  final String relationship;
  final bool isPrimary;
  final bool notifyViaCall;
  final bool notifyViaSMS;

  EmergencyContact({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.relationship,
    this.isPrimary = false,
    this.notifyViaCall = true,
    this.notifyViaSMS = true,
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      id: json['id'] as String,
      name: json['name'] as String,
      phoneNumber: json['phoneNumber'] as String,
      relationship: json['relationship'] as String,
      isPrimary: json['isPrimary'] as bool? ?? false,
      notifyViaCall: json['notifyViaCall'] as bool? ?? true,
      notifyViaSMS: json['notifyViaSMS'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phoneNumber': phoneNumber,
      'relationship': relationship,
      'isPrimary': isPrimary,
      'notifyViaCall': notifyViaCall,
      'notifyViaSMS': notifyViaSMS,
    };
  }
}
