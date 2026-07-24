import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/device/safety_hardware_bridge.dart';
import '../../core/network/api_client.dart';
import '../../core/realtime/realtime_gateways.dart';
import '../../core/services/background_guard_service.dart';
import '../../core/services/evidence_vault_service.dart';
import '../../features/safety/data/safety_repository.dart';
import '../../features/safety/domain/use_cases/dispatch_emergency_alert_use_case.dart';
import '../../features/safety/domain/use_cases/incident_projection_use_case.dart';
import '../../features/safety/domain/use_cases/threat_assessment_use_case.dart';
import '../models/domain_models.dart';
import 'safety_contacts_notifier.dart';
import 'safety_monitoring_notifier.dart';
import 'safety_sos_notifier.dart';

class SafetyState {
  final bool initializing;
  final bool monitoringEnabled;
  final bool offlineMode;
  final bool loading;
  final String? errorMessage;

  final double threatScore;
  final ThreatLevelState threatLevel;
  final GeoCoordinate currentLocation;
  final WearableDeviceState glove;
  final WearableDeviceState glasses;

  final bool sosPending;
  final int sosCountdown;
  final bool liveLocationSharing;
  final bool guardianMode;
  final bool voiceCommandEnabled;
  final bool fakeCallEnabled;
  final int alertSensitivity;

  final List<ThreatEvent> timeline;
  final List<IncidentRecord> incidents;
  final List<EmergencyContactModel> contacts;
  final List<NotificationRecordModel> notifications;
  final List<String> personalizedTips;
  final List<String> connectionLogs;

  const SafetyState({
    required this.initializing,
    required this.monitoringEnabled,
    required this.offlineMode,
    required this.loading,
    required this.errorMessage,
    required this.threatScore,
    required this.threatLevel,
    required this.currentLocation,
    required this.glove,
    required this.glasses,
    required this.sosPending,
    required this.sosCountdown,
    required this.liveLocationSharing,
    required this.guardianMode,
    required this.voiceCommandEnabled,
    required this.fakeCallEnabled,
    required this.alertSensitivity,
    required this.timeline,
    required this.incidents,
    required this.contacts,
    required this.notifications,
    required this.personalizedTips,
    required this.connectionLogs,
  });

  factory SafetyState.initial() {
    return SafetyState(
      initializing: true,
      monitoringEnabled: false,
      offlineMode: false,
      loading: false,
      errorMessage: null,
      threatScore: 12,
      threatLevel: ThreatLevelState.safe,
      currentLocation: GeoCoordinate.now(),
      glove: WearableDeviceState.initial(DeviceKind.glove),
      glasses: WearableDeviceState.initial(DeviceKind.glasses),
      sosPending: false,
      sosCountdown: 0,
      liveLocationSharing: false,
      guardianMode: false,
      voiceCommandEnabled: true,
      fakeCallEnabled: true,
      alertSensitivity: 70,
      timeline: const [],
      incidents: const [],
      contacts: const [],
      notifications: const [],
      personalizedTips: const [
        'Enable voice trigger phrase for hands-free SOS.',
        'Keep both wearables above 30% battery.',
        'Review your safe zones every week.',
      ],
      connectionLogs: const [],
    );
  }

  SafetyState copyWith({
    bool? initializing,
    bool? monitoringEnabled,
    bool? offlineMode,
    bool? loading,
    String? errorMessage,
    bool clearError = false,
    double? threatScore,
    ThreatLevelState? threatLevel,
    GeoCoordinate? currentLocation,
    WearableDeviceState? glove,
    WearableDeviceState? glasses,
    bool? sosPending,
    int? sosCountdown,
    bool? liveLocationSharing,
    bool? guardianMode,
    bool? voiceCommandEnabled,
    bool? fakeCallEnabled,
    int? alertSensitivity,
    List<ThreatEvent>? timeline,
    List<IncidentRecord>? incidents,
    List<EmergencyContactModel>? contacts,
    List<NotificationRecordModel>? notifications,
    List<String>? personalizedTips,
    List<String>? connectionLogs,
  }) {
    return SafetyState(
      initializing: initializing ?? this.initializing,
      monitoringEnabled: monitoringEnabled ?? this.monitoringEnabled,
      offlineMode: offlineMode ?? this.offlineMode,
      loading: loading ?? this.loading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      threatScore: threatScore ?? this.threatScore,
      threatLevel: threatLevel ?? this.threatLevel,
      currentLocation: currentLocation ?? this.currentLocation,
      glove: glove ?? this.glove,
      glasses: glasses ?? this.glasses,
      sosPending: sosPending ?? this.sosPending,
      sosCountdown: sosCountdown ?? this.sosCountdown,
      liveLocationSharing: liveLocationSharing ?? this.liveLocationSharing,
      guardianMode: guardianMode ?? this.guardianMode,
      voiceCommandEnabled: voiceCommandEnabled ?? this.voiceCommandEnabled,
      fakeCallEnabled: fakeCallEnabled ?? this.fakeCallEnabled,
      alertSensitivity: alertSensitivity ?? this.alertSensitivity,
      timeline: timeline ?? this.timeline,
      incidents: incidents ?? this.incidents,
      contacts: contacts ?? this.contacts,
      notifications: notifications ?? this.notifications,
      personalizedTips: personalizedTips ?? this.personalizedTips,
      connectionLogs: connectionLogs ?? this.connectionLogs,
    );
  }
}

class SafetyController extends StateNotifier<SafetyState> {
  final SafetyRepository _safetyRepository;
  final ApiClient _apiClient;
  final WebSocketGateway _webSocketGateway;
  final MQTTGateway _mqttGateway;
  final SafetyHardwareBridge _hardwareBridge;
  final BackgroundGuardService _backgroundGuardService;
  final EvidenceVaultService _evidenceVaultService;
  final ThreatAssessmentUseCase _threatAssessmentUseCase;
  final IncidentProjectionUseCase _incidentProjectionUseCase;
  final DispatchEmergencyAlertUseCase _dispatchEmergencyAlertUseCase;
  final SafetyMonitoringNotifier _monitoringNotifier;
  final SafetySosNotifier _sosNotifier;
  final SafetyContactsNotifier _contactsNotifier;

  final Uuid _uuid;

  Timer? _monitoringTimer;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  StreamSubscription<Map<String, dynamic>>? _mqttSub;
  void Function()? _removeMonitoringListener;
  void Function()? _removeSosListener;
  void Function()? _removeContactsListener;

  SafetyController({
    required SafetyRepository safetyRepository,
    required ApiClient apiClient,
    required WebSocketGateway webSocketGateway,
    required MQTTGateway mqttGateway,
    required SafetyHardwareBridge hardwareBridge,
    required BackgroundGuardService backgroundGuardService,
    required EvidenceVaultService evidenceVaultService,
    ThreatAssessmentUseCase? threatAssessmentUseCase,
    IncidentProjectionUseCase? incidentProjectionUseCase,
    DispatchEmergencyAlertUseCase? dispatchEmergencyAlertUseCase,
    SafetyMonitoringNotifier? monitoringNotifier,
    SafetySosNotifier? sosNotifier,
    SafetyContactsNotifier? contactsNotifier,
  }) : _safetyRepository = safetyRepository,
       _apiClient = apiClient,
       _webSocketGateway = webSocketGateway,
       _mqttGateway = mqttGateway,
       _hardwareBridge = hardwareBridge,
       _backgroundGuardService = backgroundGuardService,
       _evidenceVaultService = evidenceVaultService,
       _threatAssessmentUseCase =
           threatAssessmentUseCase ?? const ThreatAssessmentUseCase(),
       _incidentProjectionUseCase =
           incidentProjectionUseCase ??
           IncidentProjectionUseCase(
             threatAssessmentUseCase:
                 threatAssessmentUseCase ?? const ThreatAssessmentUseCase(),
           ),
       _dispatchEmergencyAlertUseCase =
           dispatchEmergencyAlertUseCase ??
           DispatchEmergencyAlertUseCase(
             safetyRepository: safetyRepository,
             webSocketGateway: webSocketGateway,
             mqttGateway: mqttGateway,
           ),
       _monitoringNotifier = monitoringNotifier ?? SafetyMonitoringNotifier(),
       _sosNotifier = sosNotifier ?? SafetySosNotifier(),
       _contactsNotifier =
           contactsNotifier ??
           SafetyContactsNotifier(safetyRepository: safetyRepository),
       _uuid = const Uuid(),
       super(SafetyState.initial()) {
    _removeMonitoringListener = _monitoringNotifier.addListener(
      (_) => _syncCompositeState(),
      fireImmediately: true,
    );
    _removeSosListener = _sosNotifier.addListener(
      (_) => _syncCompositeState(),
      fireImmediately: true,
    );
    _removeContactsListener = _contactsNotifier.addListener(
      (_) => _syncCompositeState(),
      fireImmediately: true,
    );
  }

  void _syncCompositeState() {
    final monitoring = _monitoringNotifier.state;
    final sos = _sosNotifier.state;
    final contacts = _contactsNotifier.state;

    state = state.copyWith(
      initializing: monitoring.initializing,
      monitoringEnabled: monitoring.monitoringEnabled,
      offlineMode: monitoring.offlineMode,
      errorMessage: monitoring.errorMessage,
      threatScore: monitoring.threatScore,
      threatLevel: monitoring.threatLevel,
      currentLocation: monitoring.currentLocation,
      glove: monitoring.glove,
      glasses: monitoring.glasses,
      sosPending: sos.sosPending,
      sosCountdown: sos.sosCountdown,
      liveLocationSharing: sos.liveLocationSharing,
      guardianMode: monitoring.guardianMode,
      voiceCommandEnabled: monitoring.voiceCommandEnabled,
      fakeCallEnabled: monitoring.fakeCallEnabled,
      alertSensitivity: monitoring.alertSensitivity,
      timeline: monitoring.timeline,
      incidents: monitoring.incidents,
      contacts: contacts.contacts,
      notifications: contacts.notifications,
      personalizedTips: monitoring.personalizedTips,
      connectionLogs: monitoring.connectionLogs,
    );
  }

  Future<void> initialize({required String userId}) async {
    final incidents = await _safetyRepository.loadIncidents();
    _monitoringNotifier.initializeLoaded(
      incidents: incidents,
      connectionLogs: _hardwareBridge.logs,
    );
    await _contactsNotifier.initialize();

    await _connectRealtime(userId);
    startMonitoring();
  }

  Future<void> _connectRealtime(String userId) async {
    try {
      await _apiClient.refreshAuthHeaderFromStore();
      final token = _apiClient.authToken;
      if (token == null || token.isEmpty) {
        throw Exception('Missing API token for realtime connection');
      }

      await _webSocketGateway.connect(
        baseUrl: _apiClient.environment.websocketBaseUrl,
        userId: userId,
        token: token,
      );
      await _mqttGateway.connect(
        host: _apiClient.environment.mqttHost,
        port: _apiClient.environment.mqttPort,
        userId: userId,
      );

      _mqttGateway.subscribe('safeher/devices/+/events');
      _mqttGateway.subscribe('safeher/devices/+/heartbeat');
      _mqttGateway.subscribe('safeher/devices/+/emergency');
      _mqttGateway.subscribe('devices/+/events');

      _wsSub?.cancel();
      _mqttSub?.cancel();

      _wsSub = _webSocketGateway.messages.listen(_onRealtimePayload);
      _mqttSub = _mqttGateway.messages.listen(_onRealtimePayload);
    } catch (error) {
      _monitoringNotifier.setRealtimeFailure(error);
    }
  }

  void _onRealtimePayload(Map<String, dynamic> payload) {
    final data = switch (payload['payload']) {
      Map<String, dynamic> value => value,
      _ => switch (payload['data']) {
        Map<String, dynamic> value => value,
        _ => payload,
      },
    };

    final source =
        (payload['topic'] ?? payload['type'] ?? data['type'] ?? 'realtime')
            .toString();
    final description =
        (data['summary'] ??
                data['description'] ??
                data['title'] ??
                'Realtime signal received')
            .toString();
    final confidence = _threatAssessmentUseCase.parseConfidence(
      data,
      fallbackThreatScore: state.threatScore,
    );
    final threatLevelRaw =
        (data['threat_level'] ?? payload['threat_level'] ?? data['severity'])
            ?.toString();
    final severity = _threatAssessmentUseCase.levelFromBackendValue(
      threatLevelRaw,
      fallbackScore: confidence * 100,
    );

    final event = ThreatEvent(
      id: _uuid.v4(),
      time: DateTime.now(),
      source: source,
      description: description,
      confidence: confidence,
      severity: severity,
    );

    _monitoringNotifier.updateRealtimeSignal(
      event: event,
      threatScore: (confidence * 100).clamp(0, 100).toDouble(),
      threatLevel: severity,
      connectionLogs: _hardwareBridge.logs,
    );
  }

  void startMonitoring() {
    _monitoringTimer?.cancel();
    _refreshLiveState();
    _monitoringTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => _refreshLiveState(),
    );

    _backgroundGuardService.start(onTick: _syncDataSafely);
    _monitoringNotifier.setMonitoringEnabled(true);
  }

  void stopMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    _backgroundGuardService.stop();
    _monitoringNotifier.setMonitoringEnabled(false);
  }

  void setOfflineMode(bool offlineMode) {
    _monitoringNotifier.setOfflineMode(offlineMode);
  }

  Future<void> _refreshLiveState() async {
    try {
      final monitoring = _monitoringNotifier.state;
      final live = await _safetyRepository.fetchLiveState();
      final liveScore = live['live_score'] is Map<String, dynamic>
          ? (live['live_score'] as Map<String, dynamic>)
          : <String, dynamic>{};

      final score =
          (liveScore['score'] as num?)?.toDouble() ?? monitoring.threatScore;
      final level = _threatAssessmentUseCase.levelFromBackendValue(
        liveScore['level']?.toString(),
        fallbackScore: score,
      );

      final recentRaw = live['recent_incidents'];
      final recentIncidents = recentRaw is List
          ? recentRaw
                .whereType<Map>()
                .map(
                  (item) => _incidentProjectionUseCase.fromLiveState(
                    json: item.cast<String, dynamic>(),
                    currentLocation: monitoring.currentLocation,
                    fallbackThreatScore: monitoring.threatScore,
                    nextId: _uuid.v4,
                  ),
                )
                .toList()
          : const <IncidentRecord>[];

      final mergedIncidents = <IncidentRecord>[
        ...recentIncidents,
        ...monitoring.incidents.where(
          (existing) =>
              !recentIncidents.any((incoming) => incoming.id == existing.id),
        ),
      ];

      _monitoringNotifier.updateLiveState(
        score: score.clamp(0, 100).toDouble(),
        level: level,
        incidents: mergedIncidents,
        connectionLogs: _hardwareBridge.logs,
      );

      if (score >= monitoring.alertSensitivity && !_sosNotifier.isPending) {
        unawaited(triggerSos(auto: true));
      }
    } catch (_) {
      _monitoringNotifier.updateConnectionLogs(_hardwareBridge.logs);
    }
  }

  Future<List<BluetoothDevice>> scanWearables() {
    return _hardwareBridge.scanWearables();
  }

  Future<bool> pairWearable({
    required DeviceKind kind,
    required BluetoothDevice device,
  }) async {
    final connected = await _hardwareBridge.pairWearable(
      device: device,
      kind: kind,
    );
    if (connected) {
      final monitoring = _monitoringNotifier.state;
      final updated =
          (kind == DeviceKind.glove ? monitoring.glove : monitoring.glasses)
              .copyWith(
                connected: true,
                battery: kind == DeviceKind.glove ? 89 : 76,
                signalStrength: 81,
                diagnostics: 'Connected and healthy',
                lastSync: DateTime.now(),
              );

      _monitoringNotifier.setWearableConnected(
        kind: kind,
        wearable: updated,
        connectionLogs: _hardwareBridge.logs,
      );
    }

    return connected;
  }

  Future<String> runDiagnostics(DeviceKind kind) async {
    final report = await _hardwareBridge.runDiagnostics(kind);
    _monitoringNotifier.updateConnectionLogs(_hardwareBridge.logs);
    return report;
  }

  Future<void> calibrateWearable(DeviceKind kind) async {
    await _hardwareBridge.calibrate(kind);
    _monitoringNotifier.updateConnectionLogs(_hardwareBridge.logs);
  }

  Future<void> triggerSos({bool auto = false}) async {
    _sosNotifier.start(auto: auto, onDispatch: () => _dispatchEmergency(auto));
  }

  void cancelSos() {
    _sosNotifier.cancel();
  }

  Future<void> _dispatchEmergency(bool auto) async {
    final monitoring = _monitoringNotifier.state;
    final contacts = _contactsNotifier.state;
    final dispatchResult = await _dispatchEmergencyAlertUseCase(
      auto: auto,
      location: monitoring.currentLocation,
      offlineMode: monitoring.offlineMode,
      contacts: contacts.contacts,
    );

    _monitoringNotifier.appendIncident(dispatchResult.incident);
    _contactsNotifier.appendNotification(dispatchResult.notification);
    _monitoringNotifier.markEmergencyTriggered();
    if (dispatchResult.switchedToOffline) {
      _monitoringNotifier.setOfflineMode(true);
    }
    _sosNotifier.completeDispatch();
  }

  Future<void> addContact(EmergencyContactModel contact) async {
    await _contactsNotifier.addContact(contact);
  }

  Future<void> updateContact(EmergencyContactModel contact) async {
    await _contactsNotifier.updateContact(contact);
  }

  Future<void> removeContact(String contactId) async {
    await _contactsNotifier.removeContact(contactId);
  }

  Future<void> markNotificationRead(String id) async {
    await _contactsNotifier.markNotificationRead(id);
  }

  Future<String> saveEncryptedEvidence(
    Uint8List bytes, {
    required String extension,
    required Map<String, dynamic> metadata,
  }) {
    return _evidenceVaultService.saveEncryptedEvidence(
      bytes: bytes,
      extension: extension,
      metadata: metadata,
    );
  }

  void setAlertSensitivity(int value) {
    _monitoringNotifier.setAlertSensitivity(value);
  }

  void setVoiceCommandEnabled(bool enabled) {
    _monitoringNotifier.setVoiceCommandEnabled(enabled);
  }

  void setFakeCallEnabled(bool enabled) {
    _monitoringNotifier.setFakeCallEnabled(enabled);
  }

  void setGuardianMode(bool enabled) {
    _monitoringNotifier.setGuardianMode(enabled);
  }

  Future<void> _syncDataSafely() async {
    final monitoring = _monitoringNotifier.state;
    if (monitoring.offlineMode) {
      return;
    }

    try {
      await _safetyRepository.syncHeartbeat(
        threatScore: monitoring.threatScore,
        location: monitoring.currentLocation,
      );
    } catch (_) {
      _monitoringNotifier.setOfflineMode(true);
    }
  }

  @override
  void dispose() {
    _monitoringTimer?.cancel();
    _wsSub?.cancel();
    _mqttSub?.cancel();
    _removeMonitoringListener?.call();
    _removeSosListener?.call();
    _removeContactsListener?.call();
    _monitoringNotifier.dispose();
    _sosNotifier.dispose();
    _contactsNotifier.dispose();
    _backgroundGuardService.stop();
    super.dispose();
  }
}
