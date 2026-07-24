/// Model for emergency alerts sent through multi-channel alert system
class EmergencyAlert {
  final String alertId;
  final String userId;
  final String alertType; // 'AUTOMATIC', 'MANUAL', 'ESCALATION'
  final String severity; // 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL'
  final String status; // 'PENDING', 'SENT', 'ACKNOWLEDGED', 'RESOLVED'
  final String message;
  final Map<String, dynamic> location;
  final DateTime timestamp;
  final String? emergencyId;
  final List<String> notificationChannels;
  final Map<String, dynamic>? contactsNotified;
  final Map<String, dynamic>? evidenceIds;
  final Map<String, dynamic>? metadata;

  const EmergencyAlert({
    required this.alertId,
    required this.userId,
    required this.alertType,
    required this.severity,
    required this.status,
    required this.message,
    required this.location,
    required this.timestamp,
    this.emergencyId,
    this.notificationChannels = const [],
    this.contactsNotified,
    this.evidenceIds,
    this.metadata,
  });

  factory EmergencyAlert.fromJson(Map<String, dynamic> json) {
    return EmergencyAlert(
      alertId: json['alert_id'] ?? '',
      userId: json['user_id'] ?? '',
      alertType: json['alert_type'] ?? 'AUTOMATIC',
      severity: json['severity'] ?? 'MEDIUM',
      status: json['status'] ?? 'PENDING',
      message: json['message'] ?? '',
      location: json['location'] ?? {},
      timestamp:
          DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      emergencyId: json['emergency_id'],
      notificationChannels:
          List<String>.from(json['notification_channels'] ?? []),
      contactsNotified: json['contacts_notified'],
      evidenceIds: json['evidence_ids'],
      metadata: json['metadata'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'alert_id': alertId,
      'user_id': userId,
      'alert_type': alertType,
      'severity': severity,
      'status': status,
      'message': message,
      'location': location,
      'timestamp': timestamp.toIso8601String(),
      if (emergencyId != null) 'emergency_id': emergencyId,
      'notification_channels': notificationChannels,
      if (contactsNotified != null) 'contacts_notified': contactsNotified,
      if (evidenceIds != null) 'evidence_ids': evidenceIds,
      if (metadata != null) 'metadata': metadata,
    };
  }

  /// Check if this alert is critical
  bool get isCritical => severity == 'CRITICAL';

  /// Check if this alert requires immediate action
  bool get requiresAction =>
      status == 'PENDING' && (severity == 'HIGH' || severity == 'CRITICAL');

  /// Check if alert has been acknowledged
  bool get isAcknowledged => status == 'ACKNOWLEDGED' || status == 'RESOLVED';

  /// Get formatted location string
  String get locationString {
    final lat = location['latitude'];
    final lng = location['longitude'];
    final address = location['address'];

    if (address != null && address.toString().isNotEmpty) {
      return address.toString();
    } else if (lat != null && lng != null) {
      return 'Lat: ${lat.toStringAsFixed(6)}, Lng: ${lng.toStringAsFixed(6)}';
    } else {
      return 'Location unknown';
    }
  }

  /// Get formatted notification channels string
  String get channelsString {
    if (notificationChannels.isEmpty) {
      return 'No notifications sent';
    }

    final channelNames = notificationChannels.map((channel) {
      switch (channel.toLowerCase()) {
        case 'sms':
          return 'SMS';
        case 'call':
          return 'Voice Call';
        case 'email':
          return 'Email';
        case 'push':
          return 'Push Notification';
        case 'whatsapp':
          return 'WhatsApp';
        default:
          return channel.toUpperCase();
      }
    }).toList();

    return channelNames.join(', ');
  }

  /// Get time since alert was created
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  /// Create a copy with updated fields
  EmergencyAlert copyWith({
    String? alertId,
    String? userId,
    String? alertType,
    String? severity,
    String? status,
    String? message,
    Map<String, dynamic>? location,
    DateTime? timestamp,
    String? emergencyId,
    List<String>? notificationChannels,
    Map<String, dynamic>? contactsNotified,
    Map<String, dynamic>? evidenceIds,
    Map<String, dynamic>? metadata,
  }) {
    return EmergencyAlert(
      alertId: alertId ?? this.alertId,
      userId: userId ?? this.userId,
      alertType: alertType ?? this.alertType,
      severity: severity ?? this.severity,
      status: status ?? this.status,
      message: message ?? this.message,
      location: location ?? this.location,
      timestamp: timestamp ?? this.timestamp,
      emergencyId: emergencyId ?? this.emergencyId,
      notificationChannels: notificationChannels ?? this.notificationChannels,
      contactsNotified: contactsNotified ?? this.contactsNotified,
      evidenceIds: evidenceIds ?? this.evidenceIds,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'EmergencyAlert(id: $alertId, severity: $severity, status: $status, type: $alertType)';
  }
}
