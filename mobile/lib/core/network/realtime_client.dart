import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';
import 'api_client.dart';
import 'auth_token_store.dart';
import 'pinned_socket.dart';

enum RealtimeConnectionStatus { connecting, connected, disconnected }

/// Real client for the backend's live alerts feed —
/// `WS /api/v1/ws/alerts/{user_id}?ticket=<short-lived>` (see
/// `fastapi_app/routers/ws.py`). Broadcasts only fire on genuine backend
/// events (`threat_alert` from the AI pipeline, `emergency_alert` from a
/// real SOS) — there is no continuous sensor stream to simulate, so this
/// client is deliberately just "connect, listen, reconnect on drop."
///
/// ## Why a ticket and not the access token
///
/// A WebSocket handshake carries no `Authorization` header when it is opened
/// from a browser — the JavaScript API has nowhere to put one — so whatever
/// authenticates it has to travel in the URL. That is the worst place for a
/// credential: query strings are written into proxy and access logs, kept in
/// history, and passed on in referrers.
///
/// This used to send the access token there, which put a fifteen-minute
/// credential in every log between the phone and the app. It now asks
/// `POST /ws/ticket` over ordinary authenticated HTTP — where the token stays
/// in a header — and spends the reply on the handshake. The ticket lives about
/// thirty seconds and opens nothing but this feed, so a copy recovered from a
/// log is already useless.
///
/// A fresh ticket is fetched per attempt, including every reconnect: one that
/// was minted before a long backoff would have expired by the time it was
/// used.
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

    // One authenticated call gives both halves of the handshake: who we are,
    // and a credential short-lived enough to survive being logged. Asking for
    // it per attempt is deliberate — see the class doc.
    String userId;
    String ticket;
    try {
      final response = await _apiClient.dio.post('/ws/ticket');
      ticket = response.data['ticket'] as String;
      userId = response.data['user_id'] as String;
    } catch (_) {
      _statusController.add(RealtimeConnectionStatus.disconnected);
      _scheduleReconnect();
      return;
    }
    if (_disposed) return;

    final uri = _wsUri(userId: userId, ticket: ticket);
    try {
      // web_socket_channel 2.4.0 has no connection-ready future — the
      // handshake happens in the background. Wiring up the listener is
      // what actually surfaces a failed handshake (via onError/onDone),
      // so "connected" here means "actively listening", not "handshake
      // confirmed" — a bad connection still flips back to disconnected
      // promptly once the platform channel reports it.
      final channel = await connectPinnedWebSocket(uri);
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

  Uri _wsUri({required String userId, required String ticket}) {
    final apiUri = Uri.parse(AppConfig.apiBaseUrl);
    final scheme = apiUri.scheme == 'https' ? 'wss' : 'ws';
    // apiBaseUrl already ends in /api/v1 — the ws route is /api/v1/ws/alerts/{id}.
    final path = '${apiUri.path}/ws/alerts/$userId';
    return apiUri.replace(scheme: scheme, path: path, queryParameters: {'ticket': ticket});
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
