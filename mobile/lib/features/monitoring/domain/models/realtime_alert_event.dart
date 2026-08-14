enum RealtimeAlertKind { threat, emergency }

/// A single real event received over the live alerts WebSocket
/// (`WS /api/v1/ws/alerts/{user_id}`) — either a `threat_alert` (from the
/// AI threat-fusion pipeline) or an `emergency_alert` (a manual/auto SOS).
/// There is no continuous sensor stream to show between these — this is
/// the actual shape of what the backend broadcasts.
class RealtimeAlertEvent {
  const RealtimeAlertEvent({
    required this.kind,
    required this.summary,
    required this.timestamp,
    this.incidentId,
    this.threatLevel,
    this.latitude,
    this.longitude,
  });

  final RealtimeAlertKind kind;
  final String summary;
  final DateTime timestamp;
  final String? incidentId;
  final String? threatLevel;

  /// Only present on `emergency_alert` events — `fastapi_app/routers/alerts.py`
  /// broadcasts the location it was given, which is null whenever the
  /// dispatching client had no GPS fix.
  final double? latitude;
  final double? longitude;

  bool get hasLocation => latitude != null && longitude != null;

  static RealtimeAlertEvent? fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    final kind = switch (type) {
      'threat_alert' => RealtimeAlertKind.threat,
      'emergency_alert' => RealtimeAlertKind.emergency,
      _ => null,
    };
    if (kind == null) return null;
    final timestampRaw = json['timestamp'] as String?;
    final location = json['location'] as Map<String, dynamic>?;
    return RealtimeAlertEvent(
      kind: kind,
      summary: (json['summary'] as String?) ?? 'Alert received',
      timestamp: timestampRaw != null ? (DateTime.tryParse(timestampRaw) ?? DateTime.now()) : DateTime.now(),
      incidentId: json['incident_id'] as String?,
      threatLevel: (json['threat_level'] as String?) ?? (json['severity'] as String?),
      latitude: (location?['latitude'] as num?)?.toDouble(),
      longitude: (location?['longitude'] as num?)?.toDouble(),
    );
  }

  /// Rough visual-only score band derived from the real threat level this
  /// event actually carried — not a fabricated measurement, just a mapping
  /// so the existing gauge widget has something to point at.
  double? get gaugeScore => switch (threatLevel?.toLowerCase()) {
    'critical' => 0.95,
    'high' => 0.7,
    'medium' => 0.5,
    'low' => 0.2,
    _ => null,
  };
}
