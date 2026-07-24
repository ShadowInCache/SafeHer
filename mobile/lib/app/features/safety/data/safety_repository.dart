import '../../../shared/models/domain_models.dart';

abstract class SafetyRepository {
  Future<List<IncidentRecord>> loadIncidents();

  Future<List<EmergencyContactModel>> loadContacts();

  Future<List<NotificationRecordModel>> loadNotifications();

  Future<void> saveIncident(IncidentRecord incident);

  Future<void> saveContact(EmergencyContactModel contact);

  Future<void> deleteContact(String contactId);

  Future<void> saveNotification(NotificationRecordModel notification);

  Future<void> sendEmergencyAlert({
    required IncidentRecord incident,
    required List<EmergencyContactModel> contacts,
    required bool autoTriggered,
  });

  Future<void> syncHeartbeat({
    required double threatScore,
    required GeoCoordinate location,
  });

  Future<Map<String, dynamic>> fetchLiveState();
}
