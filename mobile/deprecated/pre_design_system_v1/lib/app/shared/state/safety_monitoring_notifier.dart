import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/domain_models.dart';

class SafetyMonitoringState {
  final bool initializing;
  final bool monitoringEnabled;
  final bool offlineMode;
  final String? errorMessage;
  final double threatScore;
  final ThreatLevelState threatLevel;
  final GeoCoordinate currentLocation;
  final WearableDeviceState glove;
  final WearableDeviceState glasses;
  final bool guardianMode;
  final bool voiceCommandEnabled;
  final bool fakeCallEnabled;
  final int alertSensitivity;
  final List<ThreatEvent> timeline;
  final List<IncidentRecord> incidents;
  final List<String> personalizedTips;
  final List<String> connectionLogs;

  const SafetyMonitoringState({
    required this.initializing,
    required this.monitoringEnabled,
    required this.offlineMode,
    required this.errorMessage,
    required this.threatScore,
    required this.threatLevel,
    required this.currentLocation,
    required this.glove,
    required this.glasses,
    required this.guardianMode,
    required this.voiceCommandEnabled,
    required this.fakeCallEnabled,
    required this.alertSensitivity,
    required this.timeline,
    required this.incidents,
    required this.personalizedTips,
    required this.connectionLogs,
  });

  factory SafetyMonitoringState.initial() {
    return SafetyMonitoringState(
      initializing: true,
      monitoringEnabled: false,
      offlineMode: false,
      errorMessage: null,
      threatScore: 12,
      threatLevel: ThreatLevelState.safe,
      currentLocation: GeoCoordinate.now(),
      glove: WearableDeviceState.initial(DeviceKind.glove),
      glasses: WearableDeviceState.initial(DeviceKind.glasses),
      guardianMode: false,
      voiceCommandEnabled: true,
      fakeCallEnabled: true,
      alertSensitivity: 70,
      timeline: const [],
      incidents: const [],
      personalizedTips: const [
        'Enable voice trigger phrase for hands-free SOS.',
        'Keep both wearables above 30% battery.',
        'Review your safe zones every week.',
      ],
      connectionLogs: const [],
    );
  }

  SafetyMonitoringState copyWith({
    bool? initializing,
    bool? monitoringEnabled,
    bool? offlineMode,
    String? errorMessage,
    bool clearError = false,
    double? threatScore,
    ThreatLevelState? threatLevel,
    GeoCoordinate? currentLocation,
    WearableDeviceState? glove,
    WearableDeviceState? glasses,
    bool? guardianMode,
    bool? voiceCommandEnabled,
    bool? fakeCallEnabled,
    int? alertSensitivity,
    List<ThreatEvent>? timeline,
    List<IncidentRecord>? incidents,
    List<String>? personalizedTips,
    List<String>? connectionLogs,
  }) {
    return SafetyMonitoringState(
      initializing: initializing ?? this.initializing,
      monitoringEnabled: monitoringEnabled ?? this.monitoringEnabled,
      offlineMode: offlineMode ?? this.offlineMode,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      threatScore: threatScore ?? this.threatScore,
      threatLevel: threatLevel ?? this.threatLevel,
      currentLocation: currentLocation ?? this.currentLocation,
      glove: glove ?? this.glove,
      glasses: glasses ?? this.glasses,
      guardianMode: guardianMode ?? this.guardianMode,
      voiceCommandEnabled: voiceCommandEnabled ?? this.voiceCommandEnabled,
      fakeCallEnabled: fakeCallEnabled ?? this.fakeCallEnabled,
      alertSensitivity: alertSensitivity ?? this.alertSensitivity,
      timeline: timeline ?? this.timeline,
      incidents: incidents ?? this.incidents,
      personalizedTips: personalizedTips ?? this.personalizedTips,
      connectionLogs: connectionLogs ?? this.connectionLogs,
    );
  }
}

class SafetyMonitoringNotifier extends StateNotifier<SafetyMonitoringState> {
  SafetyMonitoringNotifier() : super(SafetyMonitoringState.initial());

  void initializeLoaded({
    required List<IncidentRecord> incidents,
    required List<String> connectionLogs,
  }) {
    state = state.copyWith(
      initializing: false,
      incidents: incidents,
      connectionLogs: connectionLogs,
      clearError: true,
    );
  }

  void setRealtimeFailure(Object error) {
    state = state.copyWith(errorMessage: 'Realtime connection failed: $error');
  }

  void updateRealtimeSignal({
    required ThreatEvent event,
    required double threatScore,
    required ThreatLevelState threatLevel,
    required List<String> connectionLogs,
  }) {
    final updatedTimeline = [event, ...state.timeline].take(40).toList();
    state = state.copyWith(
      timeline: updatedTimeline,
      threatScore: threatScore,
      threatLevel: threatLevel,
      connectionLogs: connectionLogs,
    );
  }

  void updateLiveState({
    required double score,
    required ThreatLevelState level,
    required List<IncidentRecord> incidents,
    required List<String> connectionLogs,
  }) {
    state = state.copyWith(
      threatScore: score,
      threatLevel: level,
      incidents: incidents,
      connectionLogs: connectionLogs,
    );
  }

  void setMonitoringEnabled(bool enabled) {
    state = state.copyWith(monitoringEnabled: enabled);
  }

  void setOfflineMode(bool offlineMode) {
    state = state.copyWith(offlineMode: offlineMode);
  }

  void appendIncident(IncidentRecord incident) {
    state = state.copyWith(incidents: [incident, ...state.incidents]);
  }

  void markEmergencyTriggered() {
    state = state.copyWith(
      threatScore: 95,
      threatLevel: ThreatLevelState.danger,
    );
  }

  void setAlertSensitivity(int value) {
    state = state.copyWith(alertSensitivity: value.clamp(40, 95));
  }

  void setVoiceCommandEnabled(bool enabled) {
    state = state.copyWith(voiceCommandEnabled: enabled);
  }

  void setFakeCallEnabled(bool enabled) {
    state = state.copyWith(fakeCallEnabled: enabled);
  }

  void setGuardianMode(bool enabled) {
    state = state.copyWith(guardianMode: enabled);
  }

  void updateConnectionLogs(List<String> logs) {
    state = state.copyWith(connectionLogs: logs);
  }

  void setWearableConnected({
    required DeviceKind kind,
    required WearableDeviceState wearable,
    required List<String> connectionLogs,
  }) {
    state = kind == DeviceKind.glove
        ? state.copyWith(glove: wearable, connectionLogs: connectionLogs)
        : state.copyWith(glasses: wearable, connectionLogs: connectionLogs);
  }
}
