import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../data/services/ble_service.dart';
import '../../data/services/mqtt_service.dart';
import '../../data/models/sensor_data_simplified.dart';

/// Device state model
class DeviceState {
  final bool gloveConnected;
  final bool glassesConnected;
  final int gloveBattery;
  final int glassesBattery;
  final int? gloveSignalStrength;
  final int? glassesSignalStrength;
  final DateTime? lastGloveSync;
  final DateTime? lastGlassesSync;
  final bool mqttConnected;
  final MotionData? latestMotionData;
  final WeaponDetectionData? latestWeaponData;
  final VoiceThreatData? latestVoiceData;
  final int stressLevel; // 0-100 calculated from motion + heart rate
  final double totalRiskScore; // Weighted multi-modal risk score

  DeviceState({
    this.gloveConnected = false,
    this.glassesConnected = false,
    this.gloveBattery = 0,
    this.glassesBattery = 0,
    this.gloveSignalStrength,
    this.glassesSignalStrength,
    this.lastGloveSync,
    this.lastGlassesSync,
    this.mqttConnected = false,
    this.latestMotionData,
    this.latestWeaponData,
    this.latestVoiceData,
    this.stressLevel = 0,
    this.totalRiskScore = 0.0,
  });

  DeviceState copyWith({
    bool? gloveConnected,
    bool? glassesConnected,
    int? gloveBattery,
    int? glassesBattery,
    int? gloveSignalStrength,
    int? glassesSignalStrength,
    DateTime? lastGloveSync,
    DateTime? lastGlassesSync,
    bool? mqttConnected,
    MotionData? latestMotionData,
    WeaponDetectionData? latestWeaponData,
    VoiceThreatData? latestVoiceData,
    int? stressLevel,
    double? totalRiskScore,
  }) {
    return DeviceState(
      gloveConnected: gloveConnected ?? this.gloveConnected,
      glassesConnected: glassesConnected ?? this.glassesConnected,
      gloveBattery: gloveBattery ?? this.gloveBattery,
      glassesBattery: glassesBattery ?? this.glassesBattery,
      gloveSignalStrength: gloveSignalStrength ?? this.gloveSignalStrength,
      glassesSignalStrength: glassesSignalStrength ?? this.glassesSignalStrength,
      lastGloveSync: lastGloveSync ?? this.lastGloveSync,
      lastGlassesSync: lastGlassesSync ?? this.lastGlassesSync,
      mqttConnected: mqttConnected ?? this.mqttConnected,
      latestMotionData: latestMotionData ?? this.latestMotionData,
      latestWeaponData: latestWeaponData ?? this.latestWeaponData,
      latestVoiceData: latestVoiceData ?? this.latestVoiceData,
      stressLevel: stressLevel ?? this.stressLevel,
      totalRiskScore: totalRiskScore ?? this.totalRiskScore,
    );
  }

  /// Calculate stress level from motion variance
  /// Based on research: high motion variability indicates stress/agitation
  int calculateStressFromMotion(double? motionVariance) {
    if (motionVariance == null) return 0;
    
    // Motion variance thresholds (tuned from training data)
    if (motionVariance > 100) return 80; // Very high agitation
    if (motionVariance > 50) return 60;  // High agitation
    if (motionVariance > 25) return 40;  // Medium agitation
    if (motionVariance > 10) return 20;  // Low agitation
    return 0; // Normal/calm
  }

  /// Calculate weighted multi-modal risk score (0.0 - 1.0)
  /// Follows the architecture flowchart risk scoring logic
  double calculateTotalRiskScore() {
    double motionRisk = latestMotionData?.threatScore ?? 0.0;
    double weaponRisk = latestWeaponData?.threatScore ?? 0.0;
    double voiceRisk = latestVoiceData?.threatScore ?? 0.0;
    
    // Weighted scoring (based on research reliability)
    // Motion: 30% (97.29% accuracy)
    // Weapon: 40% (84.85% mAP - most critical)
    // Voice: 30% (68.8% accuracy)
    const double motionWeight = 0.30;
    const double weaponWeight = 0.40;
    const double voiceWeight = 0.30;
    
    double totalRisk = (motionRisk * motionWeight) +
                       (weaponRisk * weaponWeight) +
                       (voiceRisk * voiceWeight);
    
    return totalRisk.clamp(0.0, 1.0);
  }

  /// Get threat level (0-4) from total risk score
  /// Matches flowchart decision logic: Compare with Threshold → Safe/Warning/Danger
  int getThreatLevel() {
    if (totalRiskScore >= 0.8) return 4; // Critical
    if (totalRiskScore >= 0.6) return 3; // High
    if (totalRiskScore >= 0.4) return 2; // Medium
    if (totalRiskScore >= 0.2) return 1; // Low
    return 0; // Safe
  }

  /// Get confidence level for alerting
  String getConfidenceLevel() {
    if (totalRiskScore >= 0.9) return 'High';    // >90%
    if (totalRiskScore >= 0.7) return 'Medium';  // 70-90%
    return 'Low'; // <70%
  }

  /// Get connection quality based on RSSI
  String getConnectionQuality(int? rssi) {
    if (rssi == null) return 'Unknown';
    if (rssi > -60) return 'Excellent';
    if (rssi > -70) return 'Good';
    if (rssi > -80) return 'Fair';
    return 'Poor';
  }

  /// Check if any device has low battery
  bool get hasLowBattery => gloveBattery < 20 || glassesBattery < 20;

  /// Check if both devices are connected
  bool get allDevicesConnected => gloveConnected && glassesConnected;
}

/// Device provider for managing device state
class DeviceNotifier extends StateNotifier<DeviceState> {
  final BLEService _bleService = BLEService();
  final MQTTService _mqttService = MQTTService();

  DeviceNotifier() : super(DeviceState()) {
    _initializeListeners();
  }

  /// Initialize listeners for BLE and MQTT data
  void _initializeListeners() {
    // Listen to glove battery updates
    _bleService.gloveBatteryStream.listen((battery) {
      state = state.copyWith(
        gloveBattery: battery,
        lastGloveSync: DateTime.now(),
      );
    });

    // Listen to glasses battery updates
    _bleService.glassesBatteryStream.listen((battery) {
      state = state.copyWith(
        glassesBattery: battery,
        lastGlassesSync: DateTime.now(),
      );
    });

    // Listen to motion data from glove
    _bleService.gloveDataStream.listen((motionData) {
      // Calculate stress level from motion variance
      int calculatedStress = state.calculateStressFromMotion(motionData.motionVariance);
      
      // Update state with new motion data and stress
      state = state.copyWith(
        latestMotionData: motionData,
        lastGloveSync: DateTime.now(),
        stressLevel: calculatedStress,
      );
      
      // Recalculate total risk score
      _updateTotalRiskScore();
    });

    // Listen to connection status changes
    _bleService.connectionStatusStream.listen((status) {
      if (status['deviceType'] == 'glove') {
        state = state.copyWith(gloveConnected: status['isConnected']);
      } else if (status['deviceType'] == 'glasses') {
        state = state.copyWith(glassesConnected: status['isConnected']);
      }
    });

    // Listen to MQTT connection status
    _mqttService.connectionStatusStream.listen((isConnected) {
      state = state.copyWith(mqttConnected: isConnected);
    });

    // Listen to weapon detection data
    _mqttService.weaponDataStream.listen((weaponData) {
      state = state.copyWith(
        latestWeaponData: weaponData,
        lastGlassesSync: DateTime.now(),
      );
      
      // Recalculate total risk score
      _updateTotalRiskScore();
    });

    // Listen to voice threat data
    _mqttService.voiceDataStream.listen((voiceData) {
      state = state.copyWith(
        latestVoiceData: voiceData,
        lastGlassesSync: DateTime.now(),
      );
      
      // Recalculate total risk score
      _updateTotalRiskScore();
    });
  }

  /// Update total risk score based on latest sensor data
  /// Follows architecture flowchart: Risk Scoring Engine
  void _updateTotalRiskScore() {
    double newRiskScore = state.calculateTotalRiskScore();
    state = state.copyWith(totalRiskScore: newRiskScore);
    
    // Trigger immediate response if threat level is high/critical
    int threatLevel = state.getThreatLevel();
    if (threatLevel >= 3) {
      _triggerImmediateResponse(threatLevel);
    }
  }

  /// Trigger immediate response based on threat level
  /// Follows architecture flowchart: Immediate Response (Activate Shock, Trigger Buzzer)
  Future<void> _triggerImmediateResponse(int threatLevel) async {
    await _bleService.triggerImmediateResponse(threatLevel);
  }

  /// Scan for available devices
  Future<List<BluetoothDevice>> scanForDevices() async {
    return await _bleService.scanForDevices();
  }

  /// Connect to glove
  Future<bool> connectToGlove(BluetoothDevice device) async {
    final success = await _bleService.connectToDevice(device, isGlove: true);
    if (success) {
      state = state.copyWith(gloveConnected: true);
      await _updateSignalStrength();
    }
    return success;
  }

  /// Connect to glasses
  Future<bool> connectToGlasses(BluetoothDevice device) async {
    final success = await _bleService.connectToDevice(device, isGlove: false);
    if (success) {
      state = state.copyWith(glassesConnected: true);
      await _updateSignalStrength();
    }
    return success;
  }

  /// Connect to MQTT broker for WiFi data
  Future<bool> connectMQTT(String userId) async {
    final success = await _mqttService.connect(userId: userId);
    state = state.copyWith(mqttConnected: success);
    return success;
  }

  /// Update signal strength for connected devices
  Future<void> _updateSignalStrength() async {
    final gloveRssi = await _bleService.getSignalStrength(isGlove: true);
    final glassesRssi = await _bleService.getSignalStrength(isGlove: false);

    state = state.copyWith(
      gloveSignalStrength: gloveRssi,
      glassesSignalStrength: glassesRssi,
    );
  }

  /// Manually refresh battery levels
  Future<void> refreshBatteryLevels() async {
    final gloveBattery = await _bleService.readBatteryLevel(isGlove: true);
    final glassesBattery = await _bleService.readBatteryLevel(isGlove: false);

    if (gloveBattery != null) {
      state = state.copyWith(gloveBattery: gloveBattery);
    }
    if (glassesBattery != null) {
      state = state.copyWith(glassesBattery: glassesBattery);
    }
  }

  /// Disconnect from glove
  Future<void> disconnectGlove() async {
    await _bleService.disconnectDevice(isGlove: true);
    state = state.copyWith(gloveConnected: false);
  }

  /// Disconnect from glasses
  Future<void> disconnectGlasses() async {
    await _bleService.disconnectDevice(isGlove: false);
    state = state.copyWith(glassesConnected: false);
  }

  /// Disconnect all devices
  Future<void> disconnectAll() async {
    await _bleService.disconnectAll();
    await _mqttService.disconnect();
    state = DeviceState();
  }

  @override
  void dispose() {
    _bleService.dispose();
    _mqttService.dispose();
    super.dispose();
  }
}

/// Provider for device state
final deviceProvider = StateNotifierProvider<DeviceNotifier, DeviceState>((ref) {
  return DeviceNotifier();
});

/// Provider for checking if Bluetooth is available
final bluetoothAvailableProvider = FutureProvider<bool>((ref) async {
  return await BLEService().isBluetoothAvailable();
});
