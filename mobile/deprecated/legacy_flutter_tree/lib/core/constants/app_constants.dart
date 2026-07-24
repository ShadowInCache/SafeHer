class ThreatLevel {
  static const int safe = 0;
  static const int low = 1;
  static const int medium = 2;
  static const int high = 3;
  static const int critical = 4;
}

class DeviceType {
  static const String glove = 'glove';
  static const String glasses = 'glasses';
}

class AlertType {
  static const String motion = 'motion_anomaly';
  static const String weapon = 'weapon_detected';
  static const String voice = 'voice_threat';
  static const String manual = 'manual_sos';
}

class AppConstants {
  // === API ENDPOINTS (HYBRID ARCHITECTURE) ===
  // API Gateway - Single entry point for all microservices
  static const String baseUrl = 'http://localhost:5000/api/v1';

  // Legacy endpoints (maintained for backward compatibility)
  static const String motionDetectionEndpoint = '/ml/motion-detection';
  static const String weaponDetectionEndpoint = '/ml/weapon-detection';
  static const String voiceDetectionEndpoint = '/ml/voice-detection';
  static const String incidentsEndpoint = '/incidents';

  // === NEW HYBRID ARCHITECTURE ENDPOINTS ===
  // System Management
  static const String systemHealthEndpoint = '/system/health';
  static const String systemServicesEndpoint = '/system/services';

  // Emergency & Alerts (Alert Service)
  static const String emergencyAlertsEndpoint = '/alerts/emergency';
  static const String userAlertsEndpoint = '/alerts/user';

  // Threat Analysis (Threat Fusion Engine)
  static const String threatUpdatesEndpoint = '/threats/user';
  static const String realTimeThreatEndpoint = '/threats/realtime';

  // Evidence Management (Evidence Storage Service)
  static const String evidenceEndpoint = '/evidence';
  static const String evidenceUploadEndpoint = '/evidence/upload';
  static const String evidenceDownloadEndpoint = '/evidence/download';

  // Device Management (Communication Layer)
  static const String devicesEndpoint = '/devices';
  static const String deviceRegisterEndpoint = '/devices/register';
  static const String sensorDataEndpoint = '/sensors/data';

  // User Management
  static const String userLocationEndpoint = '/users/location';
  static const String emergencyContactsEndpoint = '/users/emergency-contacts';

  // === REAL-TIME COMMUNICATION ===
  // WebSocket Server (Communication Layer)
  static const String webSocketUrl = 'ws://localhost:8765/ws/emergency';

  // MQTT Broker (Communication Layer)
  static const String mqttBroker = 'localhost';
  static const int mqttPort = 1883;
  static const int mqttPortSSL = 8883;

  // === MQTT TOPICS (DEVICE COMMUNICATION) ===
  // Device-specific topics
  static const String motionTopic = 'safeher/motion';
  static const String videoTopic = 'safeher/video';
  static const String audioTopic = 'safeher/audio';
  static const String gpsTopic = 'safeher/gps';

  // Emergency topics
  static const String emergencyTopic = 'safeher/emergency';
  static const String alertTopic = 'safeher/alerts';

  // Device status topics
  static const String deviceStatusTopic = 'safeher/device/status';
  static const String deviceHealthTopic = 'safeher/device/health';

  // === MICROSERVICE PORTS (DEVELOPMENT) ===
  static const int apiGatewayPort = 5000;
  static const int motionServicePort = 8001;
  static const int visionServicePort = 8002;
  static const int threatFusionPort = 8003;
  static const int alertServicePort = 8004;
  static const int evidenceServicePort = 8005;
  static const int voiceServicePort = 8006;
  static const int websocketServicePort = 8765;

  // === THREAT DETECTION THRESHOLDS ===
  static const double motionThreshold = 0.75; // 75% confidence
  static const double weaponThreshold = 0.80; // 80% confidence
  static const double voiceThreshold = 0.70; // 70% confidence
  static const double combinedThreatThreshold = 0.75; // Combined score

  // Timing
  static const int sosCountdownSeconds = 10;
  static const int motionBufferSeconds = 5;
  static const int videoBufferSeconds = 10;
  static const int audioWindowSeconds = 3;

  // Storage
  static const String userPrefsKey = 'user_prefs';
  static const String deviceConfigKey = 'device_config';
  static const String emergencyContactsKey = 'emergency_contacts';

  // Bluetooth
  static const String gloveServiceUuid = '0000180a-0000-1000-8000-00805f9b34fb';
  static const String glassesServiceUuid =
      '0000180f-0000-1000-8000-00805f9b34fb';
  static const String bleServiceUuid =
      '0000180a-0000-1000-8000-00805f9b34fb'; // Same as glove for now
  static const String bleCharacteristicUuid =
      '00002a37-0000-1000-8000-00805f9b34fb'; // Heart rate characteristic

  // Animation Durations
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 400);
  static const Duration longAnimation = Duration(milliseconds: 600);
}
