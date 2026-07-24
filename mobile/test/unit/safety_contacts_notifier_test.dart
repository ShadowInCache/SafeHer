import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/app/features/safety/data/safety_repository.dart';
import 'package:safeher_app/app/shared/models/domain_models.dart';
import 'package:safeher_app/app/shared/state/safety_contacts_notifier.dart';

class _InMemorySafetyRepository implements SafetyRepository {
  final List<IncidentRecord> incidents = [];
  final List<EmergencyContactModel> contacts = [];
  final List<NotificationRecordModel> notifications = [];

  @override
  Future<void> deleteContact(String contactId) async {
    contacts.removeWhere((c) => c.id == contactId);
  }

  @override
  Future<Map<String, dynamic>> fetchLiveState() async {
    return const {};
  }

  @override
  Future<List<EmergencyContactModel>> loadContacts() async {
    return List<EmergencyContactModel>.from(contacts);
  }

  @override
  Future<List<IncidentRecord>> loadIncidents() async {
    return List<IncidentRecord>.from(incidents);
  }

  @override
  Future<List<NotificationRecordModel>> loadNotifications() async {
    return List<NotificationRecordModel>.from(notifications);
  }

  @override
  Future<void> saveContact(EmergencyContactModel contact) async {
    contacts.removeWhere((c) => c.id == contact.id);
    contacts.add(contact);
  }

  @override
  Future<void> saveIncident(IncidentRecord incident) async {
    incidents.add(incident);
  }

  @override
  Future<void> saveNotification(NotificationRecordModel notification) async {
    notifications.removeWhere((n) => n.id == notification.id);
    notifications.add(notification);
  }

  @override
  Future<void> sendEmergencyAlert({
    required IncidentRecord incident,
    required List<EmergencyContactModel> contacts,
    required bool autoTriggered,
  }) async {}

  @override
  Future<void> syncHeartbeat({
    required double threatScore,
    required GeoCoordinate location,
  }) async {}
}

void main() {
  test('add and remove contact updates state', () async {
    final repo = _InMemorySafetyRepository();
    final notifier = SafetyContactsNotifier(safetyRepository: repo);

    const contact = EmergencyContactModel(
      id: 'c1',
      name: 'Nisha',
      phone: '+911234567890',
      relationship: 'Friend',
      priority: 1,
    );

    await notifier.addContact(contact);
    expect(notifier.state.contacts, hasLength(1));

    await notifier.removeContact(contact.id);
    expect(notifier.state.contacts, isEmpty);
  });

  test('markNotificationRead updates read flag', () async {
    final repo = _InMemorySafetyRepository();
    final notifier = SafetyContactsNotifier(safetyRepository: repo);

    final notification = NotificationRecordModel(
      id: 'n1',
      title: 'Alert',
      body: 'Threat detected',
      time: DateTime.now(),
      severity: ThreatLevelState.warning,
      read: false,
    );

    repo.notifications.add(notification);
    await notifier.initialize();
    await notifier.markNotificationRead('n1');

    expect(notifier.state.notifications.single.read, isTrue);
  });
}
