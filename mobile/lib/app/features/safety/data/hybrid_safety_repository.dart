import '../../../core/network/api_client.dart';
import '../../../core/services/local_database_service.dart';
import '../../../shared/models/domain_models.dart';
import 'safety_repository.dart';

class HybridSafetyRepository implements SafetyRepository {
  final LocalDatabaseService _localDatabaseService;
  final ApiClient _apiClient;

  const HybridSafetyRepository({
    required LocalDatabaseService localDatabaseService,
    required ApiClient apiClient,
  }) : _localDatabaseService = localDatabaseService,
       _apiClient = apiClient;

  @override
  Future<List<IncidentRecord>> loadIncidents() async {
    try {
      final response = await _apiClient.get('/incidents/');
      final raw = response['data'] ?? response;
      if (raw is List) {
        final incidents = raw
            .whereType<Map>()
            .map((item) => _incidentFromApi(item.cast<String, dynamic>()))
            .toList();

        for (final incident in incidents) {
          await _localDatabaseService.upsertIncident(incident);
        }
        return incidents;
      }
    } catch (_) {
      // Fall back to offline cache.
    }
    return _localDatabaseService.loadIncidents();
  }

  @override
  Future<List<EmergencyContactModel>> loadContacts() async {
    try {
      final response = await _apiClient.get('/users/me/emergency-contacts');
      final raw = response['data'] ?? response;
      if (raw is List) {
        final contacts = raw
            .whereType<Map>()
            .map((item) => _contactFromApi(item.cast<String, dynamic>()))
            .toList();

        for (final contact in contacts) {
          await _localDatabaseService.upsertContact(contact);
        }
        return contacts;
      }
    } catch (_) {
      // Fall back to offline cache.
    }
    return _localDatabaseService.loadContacts();
  }

  @override
  Future<List<NotificationRecordModel>> loadNotifications() {
    return _localDatabaseService.loadNotifications();
  }

  @override
  Future<void> saveIncident(IncidentRecord incident) {
    return _localDatabaseService.upsertIncident(incident);
  }

  @override
  Future<void> saveContact(EmergencyContactModel contact) {
    return _saveContactWithRemoteSync(contact);
  }

  @override
  Future<void> deleteContact(String contactId) async {
    await _localDatabaseService.deleteContact(contactId);
    try {
      await _apiClient.delete('/users/me/emergency-contacts/$contactId');
    } catch (_) {
      // Keep local deletion for offline continuity.
    }
  }

  @override
  Future<void> saveNotification(NotificationRecordModel notification) {
    return _localDatabaseService.upsertNotification(notification);
  }

  @override
  Future<void> sendEmergencyAlert({
    required IncidentRecord incident,
    required List<EmergencyContactModel> contacts,
    required bool autoTriggered,
  }) async {
    await _apiClient.post(
      '/alerts/emergency',
      body: {
        'incident_id': incident.id,
        'auto': autoTriggered,
        'severity': incident.severity.name,
        'location': incident.location.toJson(),
        'contacts': contacts
            .map(
              (contact) => {
                'name': contact.name,
                'phone': contact.phone,
                'priority': contact.priority,
                'relationship': contact.relationship,
              },
            )
            .toList(),
        'summary': incident.summary,
        'timestamp': incident.createdAt.toIso8601String(),
      },
    );
  }

  @override
  Future<void> syncHeartbeat({
    required double threatScore,
    required GeoCoordinate location,
  }) {
    return _apiClient.post(
      '/alerts/heartbeat',
      body: {
        'timestamp': DateTime.now().toIso8601String(),
        'threat_score': threatScore,
        'location': location.toJson(),
      },
    );
  }

  @override
  Future<Map<String, dynamic>> fetchLiveState() {
    return _apiClient.get('/alerts/live');
  }

  Future<void> _saveContactWithRemoteSync(EmergencyContactModel contact) async {
    await _localDatabaseService.upsertContact(contact);

    final body = {
      'id': contact.id,
      'name': contact.name,
      'phone': contact.phone,
      'email': contact.email,
      'relationship': contact.relationship,
      'priority': contact.priority,
    };

    try {
      await _apiClient.put(
        '/users/me/emergency-contacts/${contact.id}',
        body: body,
      );
      return;
    } catch (_) {
      try {
        await _apiClient.post('/users/me/emergency-contacts', body: body);
      } catch (_) {
        // Keep local save if backend is unavailable.
      }
    }
  }

  IncidentRecord _incidentFromApi(Map<String, dynamic> json) {
    final threat = (json['threat_level'] ?? 'low').toString().toLowerCase();
    final severity = switch (threat) {
      'critical' || 'high' || 'danger' => ThreatLevelState.danger,
      'medium' || 'warning' => ThreatLevelState.warning,
      _ => ThreatLevelState.safe,
    };

    final createdAt =
        DateTime.tryParse((json['created_at'] ?? '').toString()) ??
        DateTime.now();

    return IncidentRecord(
      id: (json['id'] ?? '').toString(),
      createdAt: createdAt,
      severity: severity,
      summary: (json['description'] ?? json['title'] ?? 'Incident').toString(),
      location: GeoCoordinate(latitude: 0, longitude: 0, timestamp: createdAt),
      evidenceFiles: [
        if ((json['evidence_url'] ?? '').toString().isNotEmpty)
          (json['evidence_url']).toString(),
      ],
      synced: true,
    );
  }

  EmergencyContactModel _contactFromApi(Map<String, dynamic> json) {
    return EmergencyContactModel(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      email: json['email']?.toString(),
      relationship: (json['relationship'] ?? 'trusted_contact').toString(),
      priority: (json['priority'] as num?)?.toInt() ?? 1,
    );
  }
}
