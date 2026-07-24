import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/threat_update.dart';
import '../models/emergency_alert.dart';
import '../models/evidence_data.dart';
import 'dart:developer' as dev;

final webSocketServiceProvider = Provider<WebSocketService>(
  (ref) => WebSocketService(),
);

/// Real-time WebSocket service for communicating with SafeHer hybrid architecture
class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _channel;
  bool _isConnected = false;
  String? _userId;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;

  // Stream controllers for real-time data
  final _threatUpdateController = StreamController<ThreatUpdate>.broadcast();
  final _emergencyAlertController =
      StreamController<EmergencyAlert>.broadcast();
  final _evidenceUpdateController = StreamController<EvidenceData>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();
  final _systemStatusController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Getters for streams
  Stream<ThreatUpdate> get threatUpdateStream => _threatUpdateController.stream;
  Stream<EmergencyAlert> get emergencyAlertStream =>
      _emergencyAlertController.stream;
  Stream<EvidenceData> get evidenceUpdateStream =>
      _evidenceUpdateController.stream;
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  Stream<Map<String, dynamic>> get systemStatusStream =>
      _systemStatusController.stream;

  bool get isConnected => _isConnected;
  String? get userId => _userId;

  /// Connect to WebSocket server
  Future<bool> connect({required String userId, String? customUrl}) async {
    try {
      _userId = userId;
      final wsUrl = customUrl ?? 'ws://localhost:8765/ws/emergency/$userId';

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Listen for messages
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnection,
      );

      // Send connection auth
      await _sendMessage({
        'type': 'auth',
        'user_id': userId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      _isConnected = true;
      _reconnectAttempts = 0;
      _connectionStatusController.add(true);

      // Start heartbeat
      _startHeartbeat();

      dev.log('WebSocket connected successfully for user: $userId');
      return true;
    } catch (e) {
      dev.log('WebSocket connection failed: $e');
      _isConnected = false;
      _connectionStatusController.add(false);

      // Attempt reconnection
      _attemptReconnection();
      return false;
    }
  }

  /// Disconnect from WebSocket
  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();

    if (_channel != null) {
      await _channel!.sink.close();
    }

    _isConnected = false;
    _userId = null;
    _connectionStatusController.add(false);

    dev.log('WebSocket disconnected');
  }

  /// Send manual emergency trigger
  Future<void> triggerEmergency({
    required Map<String, dynamic> location,
    String? additionalInfo,
    List<String>? evidenceFiles,
  }) async {
    if (!_isConnected) {
      throw Exception('WebSocket not connected');
    }

    await _sendMessage({
      'type': 'emergency_trigger',
      'user_id': _userId,
      'location': location,
      'additional_info': additionalInfo,
      'evidence_files': evidenceFiles ?? [],
      'timestamp': DateTime.now().toIso8601String(),
      'source': 'mobile_app_manual',
    });
  }

  /// Send device sensor data
  Future<void> sendSensorData({
    required String deviceType, // 'glove' or 'glasses'
    required Map<String, dynamic> sensorData,
    required Map<String, dynamic> location,
  }) async {
    if (!_isConnected) {
      dev.log('WebSocket not connected, queuing sensor data');
      return;
    }

    await _sendMessage({
      'type': 'sensor_data',
      'user_id': _userId,
      'device_type': deviceType,
      'sensor_data': sensorData,
      'location': location,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Update user location
  Future<void> updateLocation(Map<String, dynamic> location) async {
    if (!_isConnected) return;

    await _sendMessage({
      'type': 'location_update',
      'user_id': _userId,
      'location': location,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Request evidence files for an incident
  Future<void> requestEvidence(String emergencyId) async {
    if (!_isConnected) return;

    await _sendMessage({
      'type': 'evidence_request',
      'user_id': _userId,
      'emergency_id': emergencyId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Acknowledge emergency alert
  Future<void> acknowledgeAlert(String alertId) async {
    if (!_isConnected) return;

    await _sendMessage({
      'type': 'alert_acknowledgment',
      'user_id': _userId,
      'alert_id': alertId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Send message to WebSocket
  Future<void> _sendMessage(Map<String, dynamic> message) async {
    if (_channel != null && _isConnected) {
      final jsonMessage = json.encode(message);
      _channel!.sink.add(jsonMessage);
    }
  }

  /// Handle incoming messages
  void _handleMessage(dynamic data) {
    try {
      final message = json.decode(data.toString()) as Map<String, dynamic>;
      final messageType = message['type'] as String?;

      dev.log('Received WebSocket message: $messageType');

      switch (messageType) {
        case 'threat_update':
          _handleThreatUpdate(message);
          break;
        case 'emergency_alert':
          _handleEmergencyAlert(message);
          break;
        case 'evidence_update':
          _handleEvidenceUpdate(message);
          break;
        case 'system_status':
          _handleSystemStatus(message);
          break;
        case 'heartbeat_response':
          // Heartbeat acknowledged
          break;
        case 'auth_success':
          dev.log('WebSocket authentication successful');
          break;
        case 'auth_failed':
          dev.log('WebSocket authentication failed');
          _handleError('Authentication failed');
          break;
        case 'error':
          _handleError(message['error'] ?? 'Unknown error');
          break;
        default:
          dev.log('Unknown message type: $messageType');
      }
    } catch (e) {
      dev.log('Error parsing WebSocket message: $e');
    }
  }

  /// Handle threat level updates
  void _handleThreatUpdate(Map<String, dynamic> message) {
    try {
      final threatUpdate = ThreatUpdate.fromJson(message);
      _threatUpdateController.add(threatUpdate);
    } catch (e) {
      dev.log('Error handling threat update: $e');
    }
  }

  /// Handle emergency alerts
  void _handleEmergencyAlert(Map<String, dynamic> message) {
    try {
      final emergencyAlert = EmergencyAlert.fromJson(message);
      _emergencyAlertController.add(emergencyAlert);
    } catch (e) {
      dev.log('Error handling emergency alert: $e');
    }
  }

  /// Handle evidence updates
  void _handleEvidenceUpdate(Map<String, dynamic> message) {
    try {
      final evidenceData = EvidenceData.fromJson(message);
      _evidenceUpdateController.add(evidenceData);
    } catch (e) {
      dev.log('Error handling evidence update: $e');
    }
  }

  /// Handle system status updates
  void _handleSystemStatus(Map<String, dynamic> message) {
    _systemStatusController.add(message['status'] ?? {});
  }

  /// Handle WebSocket errors
  void _handleError(dynamic error) {
    dev.log('WebSocket error: $error');
    _isConnected = false;
    _connectionStatusController.add(false);
    _attemptReconnection();
  }

  /// Handle WebSocket disconnection
  void _handleDisconnection() {
    dev.log('WebSocket disconnected');
    _isConnected = false;
    _connectionStatusController.add(false);
    _heartbeatTimer?.cancel();
    _attemptReconnection();
  }

  /// Start heartbeat to keep connection alive
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected) {
        _sendMessage({
          'type': 'heartbeat',
          'user_id': _userId,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  /// Attempt to reconnect
  void _attemptReconnection() {
    if (_reconnectAttempts >= maxReconnectAttempts || _userId == null) {
      dev.log('Max reconnection attempts reached or no user ID');
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(
      seconds: _reconnectAttempts * 2,
    ); // Exponential backoff

    debugPrint(
      'Attempting WebSocket reconnection in ${delay.inSeconds} seconds (attempt $_reconnectAttempts)',
    );

    _reconnectTimer = Timer(delay, () {
      connect(userId: _userId!);
    });
  }

  /// Dispose resources
  void dispose() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _threatUpdateController.close();
    _emergencyAlertController.close();
    _evidenceUpdateController.close();
    _connectionStatusController.close();
    _systemStatusController.close();
  }
}
