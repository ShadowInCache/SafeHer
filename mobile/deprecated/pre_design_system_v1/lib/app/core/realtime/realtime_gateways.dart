import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketGateway {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final StreamController<Map<String, dynamic>> _messages =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<bool> _status = StreamController<bool>.broadcast();
  Timer? _heartbeat;

  Stream<Map<String, dynamic>> get messages => _messages.stream;
  Stream<bool> get status => _status.stream;

  bool get isConnected => _channel != null;

  Future<void> connect({
    required String baseUrl,
    required String userId,
    required String token,
  }) async {
    await disconnect();

    final uri = Uri.parse(
      '$baseUrl/$userId',
    ).replace(queryParameters: {'token': token});
    _channel = WebSocketChannel.connect(uri);
    _subscription = _channel!.stream.listen(
      _onMessage,
      onError: (_) => _status.add(false),
      onDone: () => _status.add(false),
    );
    _status.add(true);

    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      send(type: 'ping', payload: {'user_id': userId});
    });
  }

  void _onMessage(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is Map<String, dynamic>) {
        _messages.add(decoded);
      }
    } catch (_) {
      // Ignore malformed payloads.
    }
  }

  void send({required String type, Map<String, dynamic>? payload}) {
    final channel = _channel;
    if (channel == null) {
      return;
    }

    channel.sink.add(
      jsonEncode({
        'type': type,
        'payload': payload ?? {},
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );
  }

  Future<void> disconnect() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _status.add(false);
  }

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
    await _status.close();
  }
}

class MQTTGateway {
  MqttServerClient? _client;
  final StreamController<Map<String, dynamic>> _messages =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<bool> _status = StreamController<bool>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messages.stream;
  Stream<bool> get status => _status.stream;

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<bool> connect({
    required String host,
    required int port,
    required String userId,
  }) async {
    final client =
        MqttServerClient.withPort(host, 'safeher-mobile-$userId', port)
          ..logging(on: false)
          ..keepAlivePeriod = 60
          ..autoReconnect = true
          ..onConnected = () {
            _status.add(true);
          }
          ..onDisconnected = () {
            _status.add(false);
          };

    final message = MqttConnectMessage();
    message.withClientIdentifier('safeher-mobile-$userId');
    message.startClean();
    client.connectionMessage = message;

    try {
      client.connect();
      _client = client;
      client.updates?.listen(_onUpdates);
      return isConnected;
    } catch (_) {
      _status.add(false);
      return false;
    }
  }

  void _onUpdates(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final topic = event.topic;
      final payload = event.payload as MqttPublishMessage;
      final raw = MqttPublishPayload.bytesToStringAsString(
        payload.payload.message,
      );

      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _messages.add({'topic': topic, 'data': decoded});
        }
      } catch (_) {
        _messages.add({
          'topic': topic,
          'data': {'raw': raw},
        });
      }
    }
  }

  void subscribe(String topic) {
    _client?.subscribe(topic, MqttQos.atLeastOnce);
  }

  void publish(String topic, Map<String, dynamic> data) {
    final client = _client;
    if (client == null || !isConnected) {
      return;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(data));
    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  void disconnect() {
    _client?.disconnect();
    _client = null;
    _status.add(false);
  }

  Future<void> dispose() async {
    disconnect();
    await _messages.close();
    await _status.close();
  }
}
