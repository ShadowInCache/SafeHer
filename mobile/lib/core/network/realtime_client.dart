import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';
import 'api_client.dart';
import 'auth_token_store.dart';

enum RealtimeConnectionStatus { connecting, connected, disconnected }

/// Real client for the backend's live alerts feed —
/// `WS /api/v1/ws/alerts/{user_id}?token=<jwt>` (see
/// `fastapi_app/routers/ws.py`). Broadcasts only fire on genuine backend
/// events (`threat_alert` from the AI pipeline, `emergency_alert` from a
/// real SOS) — there is no continuous sensor stream to simulate, so this
/// client is deliberately just "connect, listen, reconnect on drop."
class RealtimeAlertsClient {
  RealtimeAlertsClient({required ApiClient apiClient, required AuthTokenStore tokenStore})
    : _apiClient = apiClient,
      _tokenStore = tokenStore;

  final ApiClient _apiClient;
  final AuthTokenStore _tokenStore;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  bool _disposed = false;
  int _reconnectAttempt = 0;

  final _statusController = StreamController<RealtimeConnectionStatus>.broadcast();
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<RealtimeConnectionStatus> get status => _statusController.stream;
  Stream<Map<String, dynamic>> get events => _eventController.stream;

  Future<void> connect() async {
    if (_disposed) return;
    _statusController.add(RealtimeConnectionStatus.connecting);

    final token = await _tokenStore.readToken();
    if (token == null) {
      _statusController.add(RealtimeConnectionStatus.disconnected);
      return;
    }

    String userId;
    try {
      final me = await _apiClient.dio.get('/users/me');
      userId = me.data['id'] as String;
    } catch (_) {
      _statusController.add(RealtimeConnectionStatus.disconnected);
      _scheduleReconnect();
      return;
    }
    if (_disposed) return;

    final uri = _wsUri(userId: userId, token: token);
    try {
      // web_socket_channel 2.4.0 has no connection-ready future — the
      // handshake happens in the background. Wiring up the listener is
      // what actually surfaces a failed handshake (via onError/onDone),
      // so "connected" here means "actively listening", not "handshake
      // confirmed" — a bad connection still flips back to disconnected
      // promptly once the platform channel reports it.
      final channel = WebSocketChannel.connect(uri);
      if (_disposed) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _reconnectAttempt = 0;
      _subscription = channel.stream.listen(
        _handleMessage,
        onDone: _handleDisconnect,
        onError: (_) => _handleDisconnect(),
      );
      _statusController.add(RealtimeConnectionStatus.connected);
    } catch (_) {
      _statusController.add(RealtimeConnectionStatus.disconnected);
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> && decoded['type'] != 'pong') {
        _eventController.add(decoded);
      }
    } catch (_) {
      // Not JSON (e.g. a bare "pong") — nothing to surface.
    }
  }

  void _handleDisconnect() {
    _subscription = null;
    _channel = null;
    if (_disposed) return;
    _statusController.add(RealtimeConnectionStatus.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectAttempt = (_reconnectAttempt + 1).clamp(0, 5);
    final delay = Duration(seconds: 2 * _reconnectAttempt);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, connect);
  }

  Uri _wsUri({required String userId, required String token}) {
    final apiUri = Uri.parse(AppConfig.apiBaseUrl);
    final scheme = apiUri.scheme == 'https' ? 'wss' : 'ws';
    // apiBaseUrl already ends in /api/v1 — the ws route is /api/v1/ws/alerts/{id}.
    final path = '${apiUri.path}/ws/alerts/$userId';
    return apiUri.replace(scheme: scheme, path: path, queryParameters: {'token': token});
  }

  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    await _statusController.close();
    await _eventController.close();
  }
}
