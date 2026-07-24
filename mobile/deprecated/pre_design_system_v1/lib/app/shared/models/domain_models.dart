import 'dart:math';

enum AppRole { user, guardian, admin, police }

enum ThreatLevelState { safe, warning, danger }

enum DeviceKind { glove, glasses }

enum DeviceTransport { ble, bluetooth, wifi }

class AppUser {
  final String id;
  final String fullName;
  final String email;
  final String? phone;
  final AppRole role;

  const AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.phone,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: (json['id'] ?? json['user_id'] ?? '').toString(),
      fullName: (json['full_name'] ?? json['name'] ?? 'SafeHer User')
          .toString(),
      email: (json['email'] ?? '').toString(),
      phone: json['phone']?.toString(),
      role: _roleFromString((json['role'] ?? 'user').toString()),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'full_name': fullName,
    'email': email,
    'phone': phone,
    'role': role.name,
  };

  static AppRole _roleFromString(String role) {
    switch (role.toLowerCase()) {
      case 'guardian':
        return AppRole.guardian;
      case 'admin':
        return AppRole.admin;
      case 'police':
        return AppRole.police;
      default:
        return AppRole.user;
    }
  }
}

class GeoCoordinate {
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  const GeoCoordinate({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  factory GeoCoordinate.now() {
    return GeoCoordinate(
      latitude: 12.9716,
      longitude: 77.5946,
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'timestamp': timestamp.toIso8601String(),
  };
}

class WearableDeviceState {
  final String id;
  final DeviceKind kind;
  final String displayName;
  final bool connected;
  final int battery;
  final int signalStrength;
  final DeviceTransport transport;
  final DateTime? lastSync;
  final String diagnostics;

  const WearableDeviceState({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.connected,
    required this.battery,
    required this.signalStrength,
    required this.transport,
    this.lastSync,
    this.diagnostics = 'Healthy',
  });

  WearableDeviceState copyWith({
    bool? connected,
    int? battery,
    int? signalStrength,
    DeviceTransport? transport,
    DateTime? lastSync,
    String? diagnostics,
  }) {
    return WearableDeviceState(
      id: id,
      kind: kind,
      displayName: displayName,
      connected: connected ?? this.connected,
      battery: battery ?? this.battery,
      signalStrength: signalStrength ?? this.signalStrength,
      transport: transport ?? this.transport,
      lastSync: lastSync ?? this.lastSync,
      diagnostics: diagnostics ?? this.diagnostics,
    );
  }

  static WearableDeviceState initial(DeviceKind kind) {
    return WearableDeviceState(
      id: kind == DeviceKind.glove ? 'glove-001' : 'glasses-001',
      kind: kind,
      displayName: kind == DeviceKind.glove ? 'Smart Glove' : 'Smart Glasses',
      connected: false,
      battery: 0,
      signalStrength: 0,
      transport: kind == DeviceKind.glove
          ? DeviceTransport.ble
          : DeviceTransport.wifi,
      lastSync: null,
      diagnostics: 'Not connected',
    );
  }
}

class ThreatEvent {
  final String id;
  final DateTime time;
  final String source;
  final String description;
  final double confidence;
  final ThreatLevelState severity;

  const ThreatEvent({
    required this.id,
    required this.time,
    required this.source,
    required this.description,
    required this.confidence,
    required this.severity,
  });
}

class IncidentRecord {
  final String id;
  final DateTime createdAt;
  final ThreatLevelState severity;
  final String summary;
  final GeoCoordinate location;
  final List<String> evidenceFiles;
  final bool synced;

  const IncidentRecord({
    required this.id,
    required this.createdAt,
    required this.severity,
    required this.summary,
    required this.location,
    required this.evidenceFiles,
    required this.synced,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'severity': severity.name,
      'summary': summary,
      'latitude': location.latitude,
      'longitude': location.longitude,
      'synced': synced ? 1 : 0,
    };
  }

  factory IncidentRecord.fromJson(Map<String, dynamic> json) {
    return IncidentRecord(
      id: (json['id'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
      severity: _severityFromString((json['severity'] ?? 'safe').toString()),
      summary: (json['summary'] ?? 'Incident recorded').toString(),
      location: GeoCoordinate(
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        timestamp:
            DateTime.tryParse((json['created_at'] ?? '').toString()) ??
            DateTime.now(),
      ),
      evidenceFiles: (json['evidence_files'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      synced: (json['synced'] as int? ?? 0) == 1,
    );
  }

  static ThreatLevelState _severityFromString(String value) {
    switch (value.toLowerCase()) {
      case 'danger':
      case 'critical':
      case 'high':
        return ThreatLevelState.danger;
      case 'warning':
      case 'medium':
        return ThreatLevelState.warning;
      default:
        return ThreatLevelState.safe;
    }
  }
}

class EmergencyContactModel {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String relationship;
  final int priority;
  final bool isGuardian;

  const EmergencyContactModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.relationship,
    required this.priority,
    this.email,
    this.isGuardian = false,
  });

  EmergencyContactModel copyWith({
    String? name,
    String? phone,
    String? email,
    String? relationship,
    int? priority,
    bool? isGuardian,
  }) {
    return EmergencyContactModel(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      relationship: relationship ?? this.relationship,
      priority: priority ?? this.priority,
      isGuardian: isGuardian ?? this.isGuardian,
    );
  }
}

class NotificationRecordModel {
  final String id;
  final String title;
  final String body;
  final DateTime time;
  final ThreatLevelState severity;
  final bool read;

  const NotificationRecordModel({
    required this.id,
    required this.title,
    required this.body,
    required this.time,
    required this.severity,
    required this.read,
  });

  NotificationRecordModel copyWith({bool? read}) {
    return NotificationRecordModel(
      id: id,
      title: title,
      body: body,
      time: time,
      severity: severity,
      read: read ?? this.read,
    );
  }
}

class DashboardSnapshot {
  final double threatScore;
  final ThreatLevelState threatLevel;
  final GeoCoordinate location;
  final WearableDeviceState glove;
  final WearableDeviceState glasses;
  final List<IncidentRecord> recentIncidents;
  final List<String> safetyTips;

  const DashboardSnapshot({
    required this.threatScore,
    required this.threatLevel,
    required this.location,
    required this.glove,
    required this.glasses,
    required this.recentIncidents,
    required this.safetyTips,
  });

  factory DashboardSnapshot.mock() {
    final random = Random();
    final score = (10 + random.nextDouble() * 25).clamp(0, 100).toDouble();
    final level = score > 70
        ? ThreatLevelState.danger
        : score > 35
        ? ThreatLevelState.warning
        : ThreatLevelState.safe;

    return DashboardSnapshot(
      threatScore: score,
      threatLevel: level,
      location: GeoCoordinate.now(),
      glove: WearableDeviceState.initial(DeviceKind.glove).copyWith(
        connected: true,
        battery: 86,
        signalStrength: 77,
        diagnostics: 'Stable',
        lastSync: DateTime.now(),
      ),
      glasses: WearableDeviceState.initial(DeviceKind.glasses).copyWith(
        connected: true,
        battery: 72,
        signalStrength: 82,
        diagnostics: 'Stable',
        lastSync: DateTime.now(),
      ),
      recentIncidents: const [],
      safetyTips: const [
        'Keep your emergency contacts list up to date.',
        'Avoid low-lit shortcuts after 9 PM.',
        'Enable hands-free voice SOS command.',
      ],
    );
  }
}
