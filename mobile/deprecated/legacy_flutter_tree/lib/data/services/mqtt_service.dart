import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:flutter/material.dart';
import '../models/sensor_data_simplified.dart';

/// Service for managing MQTT connection for WiFi-based data from smart glasses
/// Enhanced with reconnection logic, QoS handling, and message buffering
class MQTTService {
  static final MQTTService _instance = MQTTService._internal();
  factory MQTTService() => _instance;
  MQTTService._internal();

  MqttServerClient? _client;
  bool _isConnected = false;
  String? _userId;
  String? _broker;
  int? _port;

  // Reconnection settings
  static const int _maxReconnectAttempts = 5;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  // Message buffering
  final List<Map<String, dynamic>> _messageBuffer = [];
  static const int _maxBufferSize = 1000;

  // Stream controllers for different data types
  final _weaponDataController =
      StreamController<WeaponDetectionData>.broadcast();
  final _voiceDataController = StreamController<VoiceThreatData>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  // Getters for streams
  Stream<WeaponDetectionData> get weaponDataStream =>
      _weaponDataController.stream;
  Stream<VoiceThreatData> get voiceDataStream => _voiceDataController.stream;
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  bool get isConnected => _isConnected;
  int get bufferedMessages => _messageBuffer.length;

  /// Connect to MQTT broker with automatic reconnection
  Future<bool> connect({
    required String userId,
    String? customBroker,
    int? customPort,
  }) async {
    _userId = userId;
    _broker = customBroker ?? 'mqtt.googleapis.com';
    _port = customPort ?? 8883;

    return _performConnection();
  }

  /// Subscribe to relevant MQTT topics
  void _subscribeToTopics(String userId) {
    if (_client == null || !_isConnected) return;

    // Subscribe to weapon detection data from glasses camera
    final weaponTopic = 'devices/$userId/glasses/weapon';
    _client!.subscribe(weaponTopic, MqttQos.atLeastOnce);
    debugPrint('📡 Subscribed to: $weaponTopic');

    // Subscribe to voice threat data from glasses microphone
    final voiceTopic = 'devices/$userId/glasses/voice';
    _client!.subscribe(voiceTopic, MqttQos.atLeastOnce);
    debugPrint('📡 Subscribed to: $voiceTopic');

    // Subscribe to general device status
    final statusTopic = 'devices/$userId/+/status';
    _client!.subscribe(statusTopic, MqttQos.atLeastOnce);
    debugPrint('📡 Subscribed to: $statusTopic');

    // Listen for incoming messages
    _client!.updates!.listen(_handleMessage);
  }

  /// Handle incoming MQTT messages
  void _handleMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (var message in messages) {
      final topic = message.topic;
      final payload = message.payload as MqttPublishMessage;
      final payloadString = MqttPublishPayload.bytesToStringAsString(
        payload.payload.message,
      );

      debugPrint('📨 Received message on topic: $topic');

      try {
        final data = jsonDecode(payloadString);

        // Route to appropriate handler
        if (topic.contains('/weapon')) {
          _handleWeaponData(data);
        } else if (topic.contains('/voice')) {
          _handleVoiceData(data);
        } else if (topic.contains('/status')) {
          _handleStatusData(data);
        }
      } catch (e) {
        debugPrint('Error parsing MQTT message: $e');
      }
    }
  }

  /// Handle weapon detection data
  void _handleWeaponData(Map<String, dynamic> data) {
    try {
      final weaponData = WeaponDetectionData(
        deviceId: data['deviceId'] ?? 'glasses_unknown',
        timestamp: DateTime.parse(
          data['timestamp'] ?? DateTime.now().toIso8601String(),
        ),
        imageUrl: data['imageUrl'],
        threatScore: (data['threatScore'] ?? 0.0).toDouble(),
        weaponDetected: data['weaponDetected'] ?? false,
        detections:
            (data['detections'] as List?)
                ?.map(
                  (d) => Detection(
                    weaponType: d['type'] ?? 'unknown',
                    confidence: (d['confidence'] ?? 0.0).toDouble(),
                    boundingBox: BoundingBox(
                      x: (d['boundingBox']?['x'] ?? 0).toDouble(),
                      y: (d['boundingBox']?['y'] ?? 0).toDouble(),
                      width: (d['boundingBox']?['width'] ?? 0).toDouble(),
                      height: (d['boundingBox']?['height'] ?? 0).toDouble(),
                    ),
                  ),
                )
                .toList() ??
            [],
      );

      _weaponDataController.add(weaponData);
      debugPrint(
        '🔫 Weapon detection: ${weaponData.weaponDetected ? "DETECTED" : "None"} (${weaponData.threatScore})',
      );
    } catch (e) {
      debugPrint('Error handling weapon data: $e');
    }
  }

  /// Handle voice threat data
  void _handleVoiceData(Map<String, dynamic> data) {
    try {
      final voiceData = VoiceThreatData(
        deviceId: data['deviceId'] ?? 'glasses_unknown',
        timestamp: DateTime.parse(
          data['timestamp'] ?? DateTime.now().toIso8601String(),
        ),
        audioUrl: data['audioUrl'],
        threatScore: (data['threatScore'] ?? 0.0).toDouble(),
        isThreatening: data['isThreatening'] ?? false,
        emotion: data['emotion'],
        emotionConfidence: (data['emotionConfidence'] ?? 0.0).toDouble(),
        transcription: data['transcription'],
      );

      _voiceDataController.add(voiceData);
      debugPrint(
        '🎤 Voice threat: ${voiceData.isThreatening ? "DETECTED" : "None"} (${voiceData.emotion})',
      );
    } catch (e) {
      debugPrint('Error handling voice data: $e');
    }
  }

  /// Handle device status updates
  void _handleStatusData(Map<String, dynamic> data) {
    debugPrint('📊 Device status update: $data');
    // Can be used to update battery, connection quality, etc.
  }

  /// Schedule reconnection with exponential backoff
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint(
        '❌ Max MQTT reconnect attempts ($_maxReconnectAttempts) reached',
      );
      return;
    }

    _reconnectAttempts++;

    // Exponential backoff: 2s, 4s, 8s, 16s, 32s
    final delaySeconds = 2 * (1 << (_reconnectAttempts - 1));
    final delay = Duration(seconds: delaySeconds);

    debugPrint(
      '⏳ Scheduling MQTT reconnect in ${delay.inSeconds}s (attempt $_reconnectAttempts/$_maxReconnectAttempts)',
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      debugPrint('🔄 Attempting MQTT reconnection...');
      _performConnection();
    });
  }

  /// Flush buffered messages when reconnected
  Future<void> _flushMessageBuffer() async {
    if (_messageBuffer.isEmpty) return;

    debugPrint('📤 Flushing ${_messageBuffer.length} buffered messages');

    for (int i = 0; i < _messageBuffer.length && i < 10; i++) {
      // Try to resend buffered messages (limit to avoid flooding)
      final msg = _messageBuffer[i];
      // Re-publish buffered message
      if (msg.containsKey('topic') && msg.containsKey('data')) {
        await publish(msg['topic'], msg['data']);
      }
    }

    _messageBuffer.clear();
  }

  /// Perform MQTT connection with proper error handling
  Future<bool> _performConnection() async {
    try {
      if (_client != null) {
        try {
          _client!.disconnect();
        } catch (e) {
          debugPrint('ℹ️ Previous connection cleanup: $e');
        }
      }

      if (_userId == null || _broker == null || _port == null) {
        debugPrint('❌ MQTT connection parameters not set');
        return false;
      }

      _client = MqttServerClient.withPort(
        _broker!,
        'safeher_app_$_userId',
        _port!,
      );
      _client!.logging(on: false);
      _client!.keepAlivePeriod = 60;
      _client!.connectTimeoutPeriod = 15000; // 15 seconds
      _client!.autoReconnect = false; // We handle reconnection manually
      _client!.onConnected = _onConnected;
      _client!.onDisconnected = _onDisconnected;
      _client!.onSubscribed = _onSubscribed;

      // Set up last will message (QoS 1 = at least once delivery)
      final connMessage = MqttConnectMessage()
          .withClientIdentifier('safeher_app_$_userId')
          .withWillTopic('devices/$_userId/status')
          .withWillMessage('offline')
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);

      _client!.connectionMessage = connMessage;

      debugPrint(
        '🔌 Connecting to MQTT broker: $_broker:$_port (attempt ${_reconnectAttempts + 1}/$_maxReconnectAttempts)',
      );

      try {
        await _client!.connect();
      } catch (e) {
        debugPrint('❌ MQTT connection error: $e');
        try {
          _client!.disconnect();
        } catch (_) {}
        _scheduleReconnect();
        return false;
      }

      if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
        _isConnected = true;
        _reconnectAttempts = 0; // Reset on success
        _connectionStatusController.add(true);
        debugPrint('✅ Connected to MQTT broker');

        // Subscribe to device topics and flush buffered messages
        _subscribeToTopics(_userId!);
        _flushMessageBuffer();

        return true;
      } else {
        debugPrint('❌ MQTT connection failed: ${_client!.connectionStatus}');
        try {
          _client!.disconnect();
        } catch (_) {}
        _scheduleReconnect();
        return false;
      }
    } catch (e) {
      debugPrint('❌ MQTT connection exception: $e');
      _scheduleReconnect();
      return false;
    }
  }

  /// Publish data to a topic
  Future<bool> publish(String topic, Map<String, dynamic> data) async {
    if (_client == null || !_isConnected) {
      debugPrint(
        '⚠️ Cannot publish to $topic: not connected to MQTT (buffering message)',
      );
      _bufferMessage({'topic': topic, 'data': data});
      return false;
    }

    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonEncode(data));

      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      debugPrint('📤 Published to $topic');
      return true;
    } catch (e) {
      debugPrint('❌ Error publishing message: $e');
      _bufferMessage({'topic': topic, 'data': data});
      return false;
    }
  }

  /// Buffer a message for later delivery
  void _bufferMessage(Map<String, dynamic> message) {
    if (_messageBuffer.length < _maxBufferSize) {
      _messageBuffer.add({
        ...message,
        'buffered_at': DateTime.now().toIso8601String(),
      });
      debugPrint(
        '💾 Buffered message (${_messageBuffer.length}/$_maxBufferSize)',
      );
    } else {
      debugPrint('⚠️ Message buffer full, dropping oldest message');
      _messageBuffer.removeAt(0);
      _messageBuffer.add(message);
    }
  }

  /// Publish sensor data from mobile app to cloud
  Future<bool> publishSensorData(
    String userId,
    String deviceType,
    Map<String, dynamic> data,
  ) async {
    final topic = 'devices/$userId/$deviceType/data';
    return await publish(topic, data);
  }

  /// Send emergency alert via MQTT
  Future<bool> sendEmergencyAlert(
    String userId,
    Map<String, dynamic> alertData,
  ) async {
    final topic = 'alerts/$userId/emergency';
    return await publish(topic, {
      ...alertData,
      'timestamp': DateTime.now().toIso8601String(),
      'priority': 'critical',
    });
  }

  /// Connection established callback
  void _onConnected() {
    debugPrint('✅ MQTT connection established');
    _isConnected = true;
    _connectionStatusController.add(true);
  }

  /// Disconnection callback
  void _onDisconnected() {
    debugPrint('⚠️ MQTT disconnected');
    _isConnected = false;
    _connectionStatusController.add(false);

    // Attempt to reconnect with exponential backoff
    if (_reconnectAttempts < _maxReconnectAttempts) {
      _scheduleReconnect();
    }
  }

  /// Subscription callback
  void _onSubscribed(String topic) {
    debugPrint('✅ Subscribed to topic: $topic');
  }

  /// Disconnect from MQTT broker
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    if (_client != null) {
      _client!.disconnect();
      _isConnected = false;
      _connectionStatusController.add(false);
      debugPrint('🔌 MQTT disconnected');
    }
  }

  /// Dispose all resources
  void dispose() {
    disconnect();
    _weaponDataController.close();
    _voiceDataController.close();
    _connectionStatusController.close();
  }
}
