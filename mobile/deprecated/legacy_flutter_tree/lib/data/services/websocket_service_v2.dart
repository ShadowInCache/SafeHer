import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../models/message.dart';
import 'dart:developer' as dev;

final webSocketServiceV2Provider =
    Provider<WebSocketServiceV2>((ref) => WebSocketServiceV2());

enum WebSocketConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

class WebSocketServiceV2 {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  WebSocketConnectionStatus _status = WebSocketConnectionStatus.disconnected;
  String? _userId;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  static const Duration reconnectDelay = Duration(seconds: 5);
  static const Duration heartbeatInterval = Duration(seconds: 30);

  // Stream controllers for different message types
  final StreamController<Message> _messageController =
      StreamController.broadcast();
  final StreamController<WebSocketMessage> _emergencyAlertController =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _userStatusController =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _typingController =
      StreamController.broadcast();
  final StreamController<WebSocketConnectionStatus> _statusController =
      StreamController.broadcast();
  final StreamController<String> _errorController =
      StreamController.broadcast();

  // Public streams
  Stream<Message> get messageStream => _messageController.stream;
  Stream<WebSocketMessage> get emergencyAlertStream =>
      _emergencyAlertController.stream;
  Stream<Map<String, dynamic>> get userStatusStream =>
      _userStatusController.stream;
  Stream<Map<String, dynamic>> get typingStream => _typingController.stream;
  Stream<WebSocketConnectionStatus> get statusStream =>
      _statusController.stream;
  Stream<String> get errorStream => _errorController.stream;

  WebSocketConnectionStatus get status => _status;
  bool get isConnected => _status == WebSocketConnectionStatus.connected;

  /// Connect to WebSocket with user authentication
  Future<void> connect(String userId, {String? authToken}) async {
    if (_status == WebSocketConnectionStatus.connecting ||
        _status == WebSocketConnectionStatus.connected) {
      return;
    }

    _userId = userId;
    _updateStatus(WebSocketConnectionStatus.connecting);

    try {
      final wsUrl = ApiConstants.getWebSocketUrl(
          ApiConstants.communicationWebSocketEndpoint(userId));

      final uri = Uri.parse(wsUrl);

      // For web socket connection with authentication
      if (authToken != null) {
        // Add token as query parameter for WebSocket authentication
        final authenticatedUri = uri.replace(
          queryParameters: {...uri.queryParameters, 'token': authToken},
        );
        _channel = WebSocketChannel.connect(authenticatedUri);
      } else {
        _channel = WebSocketChannel.connect(uri);
      }

      // Listen for messages
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnection,
      );

      _updateStatus(WebSocketConnectionStatus.connected);
      _resetReconnectAttempts();
      _startHeartbeat();

      dev.log('WebSocket connected for user: $userId');
    } catch (e) {
      dev.log('WebSocket connection error: $e');
      _updateStatus(WebSocketConnectionStatus.error);
      _errorController.add('Connection failed: $e');

      // Attempt to reconnect
      _scheduleReconnect();
    }
  }

  /// Disconnect from WebSocket
  Future<void> disconnect() async {
    _stopHeartbeat();
    _stopReconnectTimer();

    _subscription?.cancel();
    _channel?.sink.close();

    _updateStatus(WebSocketConnectionStatus.disconnected);
    _resetReconnectAttempts();

    dev.log('WebSocket disconnected');
  }

  /// Send message to chat room
  Future<void> sendMessage({
    required String chatRoomId,
    required String messageText,
    String messageType = 'text',
    List<String>? mediaUrls,
    Map<String, dynamic>? locationData,
    String? replyToMessageId,
    Map<String, dynamic>? metadata,
  }) async {
    if (!isConnected) {
      throw Exception('WebSocket not connected');
    }

    final message = {
      'type': 'send_message',
      'data': {
        'chat_room_id': chatRoomId,
        'message_text': messageText,
        'message_type': messageType,
        if (mediaUrls != null) 'media_urls': mediaUrls,
        if (locationData != null) 'location_data': locationData,
        if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
        if (metadata != null) 'metadata': metadata,
      },
      'timestamp': DateTime.now().toIso8601String(),
    };

    _sendMessage(message);
  }

  /// Join chat room for real-time updates
  Future<void> joinChatRoom(String chatRoomId) async {
    if (!isConnected) {
      throw Exception('WebSocket not connected');
    }

    final message = {
      'type': 'join_room',
      'data': {
        'chat_room_id': chatRoomId,
      },
      'timestamp': DateTime.now().toIso8601String(),
    };

    _sendMessage(message);
  }

  /// Leave chat room
  Future<void> leaveChatRoom(String chatRoomId) async {
    if (!isConnected) {
      throw Exception('WebSocket not connected');
    }

    final message = {
      'type': 'leave_room',
      'data': {
        'chat_room_id': chatRoomId,
      },
      'timestamp': DateTime.now().toIso8601String(),
    };

    _sendMessage(message);
  }

  /// Send typing indicator
  Future<void> sendTypingIndicator({
    required String chatRoomId,
    required bool isTyping,
  }) async {
    if (!isConnected) return;

    final message = {
      'type': 'typing',
      'data': {
        'chat_room_id': chatRoomId,
        'is_typing': isTyping,
      },
      'timestamp': DateTime.now().toIso8601String(),
    };

    _sendMessage(message);
  }

  /// Send emergency alert
  Future<void> sendEmergencyAlert({
    required String alertType,
    required List<String> recipientIds,
    Map<String, dynamic>? locationData,
    String? additionalInfo,
  }) async {
    if (!isConnected) {
      throw Exception('WebSocket not connected');
    }

    final message = {
      'type': 'emergency_alert',
      'data': {
        'alert_type': alertType,
        'recipient_ids': recipientIds,
        if (locationData != null) 'location_data': locationData,
        if (additionalInfo != null) 'additional_info': additionalInfo,
      },
      'timestamp': DateTime.now().toIso8601String(),
    };

    _sendMessage(message);
  }

  /// Update user status
  Future<void> updateUserStatus(String status) async {
    if (!isConnected) return;

    final message = {
      'type': 'user_status',
      'data': {
        'status': status,
      },
      'timestamp': DateTime.now().toIso8601String(),
    };

    _sendMessage(message);
  }

  // Private methods

  void _sendMessage(Map<String, dynamic> message) {
    try {
      final jsonMessage = json.encode(message);
      _channel?.sink.add(jsonMessage);
    } catch (e) {
      dev.log('Error sending WebSocket message: $e');
      _errorController.add('Failed to send message: $e');
    }
  }

  void _handleMessage(dynamic rawMessage) {
    try {
      final messageData = json.decode(rawMessage.toString());
      final wsMessage = WebSocketMessage.fromJson(messageData);

      switch (wsMessage.type) {
        case 'message_received':
          _handleMessageReceived(wsMessage.data);
          break;

        case 'emergency_alert':
          _emergencyAlertController.add(wsMessage);
          break;

        case 'user_connected':
        case 'user_disconnected':
          _userStatusController.add(wsMessage.data);
          break;

        case 'typing':
          _typingController.add(wsMessage.data);
          break;

        case 'pong':
          // Heartbeat response - connection is alive
          break;

        case 'error':
          final errorMessage = wsMessage.data['message'] ?? 'Unknown error';
          _errorController.add(errorMessage);
          break;

        case 'connected':
          dev.log('WebSocket connection confirmed');
          break;

        case 'message_sent':
          dev.log('Message sent successfully: ${wsMessage.data['message_id']}');
          break;

        case 'room_joined':
          dev.log('Joined room: ${wsMessage.data['chat_room_id']}');
          break;

        default:
          dev.log('Unknown WebSocket message type: ${wsMessage.type}');
      }
    } catch (e) {
      dev.log('Error handling WebSocket message: $e');
      _errorController.add('Failed to handle message: $e');
    }
  }

  void _handleMessageReceived(Map<String, dynamic> data) {
    try {
      final messageData = data['message'];
      if (messageData != null) {
        final message = Message.fromJson(messageData);
        _messageController.add(message);
      }
    } catch (e) {
      dev.log('Error parsing received message: $e');
    }
  }

  void _handleError(dynamic error) {
    dev.log('WebSocket error: $error');
    _updateStatus(WebSocketConnectionStatus.error);
    _errorController.add('Connection error: $error');

    // Attempt to reconnect
    _scheduleReconnect();
  }

  void _handleDisconnection() {
    dev.log('WebSocket disconnected');
    _updateStatus(WebSocketConnectionStatus.disconnected);

    // Attempt to reconnect unless manually disconnected
    if (_userId != null) {
      _scheduleReconnect();
    }
  }

  void _updateStatus(WebSocketConnectionStatus status) {
    _status = status;
    _statusController.add(status);
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (timer) {
      if (isConnected) {
        _sendMessage({
          'type': 'ping',
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= maxReconnectAttempts) {
      dev.log('Max reconnect attempts reached');
      return;
    }

    _stopReconnectTimer();

    final delay = reconnectDelay * (_reconnectAttempts + 1);
    _reconnectTimer = Timer(delay, () {
      if (_userId != null) {
        _reconnectAttempts++;
        debugPrint('Attempting to reconnect... (attempt $_reconnectAttempts)');
        connect(_userId!);
      }
    });
  }

  void _stopReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _resetReconnectAttempts() {
    _reconnectAttempts = 0;
  }

  /// Dispose all resources
  void dispose() {
    disconnect();

    _messageController.close();
    _emergencyAlertController.close();
    _userStatusController.close();
    _typingController.close();
    _statusController.close();
    _errorController.close();
  }
}

/// WebSocket message wrapper for type safety
class WebSocketMessage {
  final String type;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  WebSocketMessage({
    required this.type,
    required this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory WebSocketMessage.fromJson(Map<String, dynamic> json) {
    return WebSocketMessage(
      type: json['type'] ?? '',
      data: json['data'] ?? <String, dynamic>{},
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
