import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/app_environment.dart';
import 'core/device/device_connectivity_service.dart';
import 'core/firebase/firebase_support.dart';
import 'core/network/api_client.dart';
import 'core/realtime/realtime_gateways.dart';
import 'core/services/background_guard_service.dart';
import 'core/services/biometric_service.dart';
import 'core/services/encryption_service.dart';
import 'core/services/evidence_vault_service.dart';
import 'core/services/local_database_service.dart';
import 'core/services/permissions_service.dart';
import 'core/services/secure_store.dart';

class BootstrapBundle {
  final AppEnvironment environment;
  final SharedPreferences sharedPreferences;
  final SecureStore secureStore;
  final BiometricService biometricService;
  final EncryptionService encryptionService;
  final EvidenceVaultService evidenceVaultService;
  final LocalDatabaseService localDatabaseService;
  final PermissionsService permissionsService;
  final BackgroundGuardService backgroundGuardService;
  final ApiClient apiClient;
  final WebSocketGateway webSocketGateway;
  final MQTTGateway mqttGateway;
  final DeviceConnectivityService deviceConnectivityService;
  final FirebaseSupport firebaseSupport;
  final bool firebaseReady;

  const BootstrapBundle({
    required this.environment,
    required this.sharedPreferences,
    required this.secureStore,
    required this.biometricService,
    required this.encryptionService,
    required this.evidenceVaultService,
    required this.localDatabaseService,
    required this.permissionsService,
    required this.backgroundGuardService,
    required this.apiClient,
    required this.webSocketGateway,
    required this.mqttGateway,
    required this.deviceConnectivityService,
    required this.firebaseSupport,
    required this.firebaseReady,
  });

  static Future<BootstrapBundle> initialize(AppEnvironment environment) async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final secureStore = SecureStore();
    final biometricService = BiometricService();
    final encryptionService = EncryptionService(secureStore);
    final evidenceVaultService = EvidenceVaultService(encryptionService);
    final localDatabase = LocalDatabaseService();
    await localDatabase.initialize();

    final permissionsService = PermissionsService();
    final backgroundGuardService = BackgroundGuardService();
    final apiClient = ApiClient(
      environment: environment,
      secureStore: secureStore,
    );
    await apiClient.refreshAuthHeaderFromStore();

    final webSocketGateway = WebSocketGateway();
    final mqttGateway = MQTTGateway();
    final deviceConnectivityService = DeviceConnectivityService();
    final firebaseSupport = FirebaseSupport();
    final firebaseReady = await firebaseSupport.initialize();

    return BootstrapBundle(
      environment: environment,
      sharedPreferences: sharedPreferences,
      secureStore: secureStore,
      biometricService: biometricService,
      encryptionService: encryptionService,
      evidenceVaultService: evidenceVaultService,
      localDatabaseService: localDatabase,
      permissionsService: permissionsService,
      backgroundGuardService: backgroundGuardService,
      apiClient: apiClient,
      webSocketGateway: webSocketGateway,
      mqttGateway: mqttGateway,
      deviceConnectivityService: deviceConnectivityService,
      firebaseSupport: firebaseSupport,
      firebaseReady: firebaseReady,
    );
  }
}
