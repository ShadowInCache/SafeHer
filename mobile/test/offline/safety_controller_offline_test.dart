import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/app/core/config/app_environment.dart';
import 'package:safeher_app/app/core/device/device_connectivity_service.dart';
import 'package:safeher_app/app/core/device/safety_hardware_bridge.dart';
import 'package:safeher_app/app/core/network/api_client.dart';
import 'package:safeher_app/app/core/realtime/realtime_gateways.dart';
import 'package:safeher_app/app/core/services/background_guard_service.dart';
import 'package:safeher_app/app/core/services/encryption_service.dart';
import 'package:safeher_app/app/core/services/evidence_vault_service.dart';
import 'package:safeher_app/app/core/services/secure_store.dart';
import 'package:safeher_app/app/features/safety/data/safety_repository.dart';
import 'package:safeher_app/app/shared/models/domain_models.dart';
import 'package:safeher_app/app/shared/state/safety_controller.dart';

const _environment = AppEnvironment(
  flavor: AppFlavor.development,
  apiBaseUrl: 'https://api.safeher.test',
  websocketBaseUrl: 'wss://api.safeher.test/ws',
  mqttHost: 'mqtt.safeher.test',
  mqttPort: 1883,
  enableVerboseLogs: true,
  useMockServices: true,
);

class _InMemorySafetyRepository implements SafetyRepository {
  final List<IncidentRecord> incidents = [];
  final List<EmergencyContactModel> contacts = [];
  final List<NotificationRecordModel> notifications = [];
  final List<String> deletedContactIds = [];

  @override
  Future<void> deleteContact(String contactId) async {
    deletedContactIds.add(contactId);
    contacts.removeWhere((contact) => contact.id == contactId);
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
    contacts.removeWhere((item) => item.id == contact.id);
    contacts.add(contact);
  }

  @override
  Future<void> saveIncident(IncidentRecord incident) async {
    incidents.removeWhere((item) => item.id == incident.id);
    incidents.add(incident);
  }

  @override
  Future<void> saveNotification(NotificationRecordModel notification) async {
    notifications.removeWhere((item) => item.id == notification.id);
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

  @override
  Future<Map<String, dynamic>> fetchLiveState() async {
    return {
      'live_score': {'score': 0.0, 'level': 'low'},
      'recent_incidents': const <Map<String, dynamic>>[],
    };
  }
}

SafetyController _buildController(_InMemorySafetyRepository repository) {
  final secureStore = SecureStore();
  return SafetyController(
    safetyRepository: repository,
    apiClient: ApiClient(environment: _environment, secureStore: secureStore),
    webSocketGateway: WebSocketGateway(),
    mqttGateway: MQTTGateway(),
    hardwareBridge: DeviceConnectivityHardwareBridge(
      DeviceConnectivityService(),
    ),
    backgroundGuardService: BackgroundGuardService(),
    evidenceVaultService: EvidenceVaultService(EncryptionService(secureStore)),
  );
}

void main() {
  test('setOfflineMode updates offline state', () {
    final repository = _InMemorySafetyRepository();
    final controller = _buildController(repository);

    controller.setOfflineMode(true);

    expect(controller.state.offlineMode, isTrue);
    controller.dispose();
  });

  test('addContact and removeContact update state and repository', () async {
    final repository = _InMemorySafetyRepository();
    final controller = _buildController(repository);

    const contact = EmergencyContactModel(
      id: 'contact-1',
      name: 'Neha',
      phone: '+911234567890',
      relationship: 'Sister',
      priority: 1,
      isGuardian: true,
    );

    await controller.addContact(contact);
    expect(controller.state.contacts, hasLength(1));
    expect(repository.contacts, hasLength(1));

    await controller.removeContact(contact.id);
    expect(controller.state.contacts, isEmpty);
    expect(repository.deletedContactIds, contains(contact.id));

    controller.dispose();
  });
}
