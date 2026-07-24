import 'package:uuid/uuid.dart';

import '../../../../core/realtime/realtime_gateways.dart';
import '../../../../shared/models/domain_models.dart';
import '../../data/safety_repository.dart';

class EmergencyDispatchResult {
  final IncidentRecord incident;
  final NotificationRecordModel notification;
  final bool switchedToOffline;

  const EmergencyDispatchResult({
    required this.incident,
    required this.notification,
    required this.switchedToOffline,
  });
}

class DispatchEmergencyAlertUseCase {
  final SafetyRepository _safetyRepository;
  final WebSocketGateway _webSocketGateway;
  final MQTTGateway _mqttGateway;
  final Uuid _uuid;

  DispatchEmergencyAlertUseCase({
    required SafetyRepository safetyRepository,
    required WebSocketGateway webSocketGateway,
    required MQTTGateway mqttGateway,
    Uuid? uuid,
  }) : _safetyRepository = safetyRepository,
       _webSocketGateway = webSocketGateway,
       _mqttGateway = mqttGateway,
       _uuid = uuid ?? const Uuid();

  Future<EmergencyDispatchResult> call({
    required bool auto,
    required GeoCoordinate location,
    required bool offlineMode,
    required List<EmergencyContactModel> contacts,
  }) async {
    final incident = IncidentRecord(
      id: _uuid.v4(),
      createdAt: DateTime.now(),
      severity: ThreatLevelState.danger,
      summary: auto
          ? 'Auto SOS activated due to sustained high threat score.'
          : 'Manual SOS activated by user.',
      location: location,
      evidenceFiles: const [],
      synced: !offlineMode,
    );

    await _safetyRepository.saveIncident(incident);

    final notification = NotificationRecordModel(
      id: _uuid.v4(),
      title: auto ? 'Auto SOS Triggered' : 'Manual SOS Triggered',
      body:
          'Emergency alert sent to guardians, trusted contacts, and nearest responders.',
      time: DateTime.now(),
      severity: ThreatLevelState.danger,
      read: false,
    );
    await _safetyRepository.saveNotification(notification);

    _webSocketGateway.send(
      type: 'emergency_alert',
      payload: {
        'severity': 'critical',
        'auto': auto,
        'location': location.toJson(),
      },
    );

    _mqttGateway.publish('safeher/emergency', {
      'incident_id': incident.id,
      'severity': 'critical',
      'location': location.toJson(),
      'timestamp': DateTime.now().toIso8601String(),
    });

    var switchedToOffline = false;
    try {
      await _safetyRepository.sendEmergencyAlert(
        incident: incident,
        contacts: contacts,
        autoTriggered: auto,
      );
    } catch (_) {
      switchedToOffline = true;
    }

    return EmergencyDispatchResult(
      incident: incident,
      notification: notification,
      switchedToOffline: switchedToOffline,
    );
  }
}
