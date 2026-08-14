import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/network_providers.dart';
import '../../../core/network/realtime_client.dart';
import '../domain/models/realtime_alert_event.dart';

part 'monitoring_providers.g.dart';

enum MonitoringConnectionStatus { connecting, connected, disconnected }

class LiveMonitoringState {
  const LiveMonitoringState({required this.status, required this.events});

  final MonitoringConnectionStatus status;

  /// Most recent first, bounded — every entry is a real event this session
  /// actually received over the WebSocket, never synthesized.
  final List<RealtimeAlertEvent> events;

  LiveMonitoringState copyWith({MonitoringConnectionStatus? status, List<RealtimeAlertEvent>? events}) {
    return LiveMonitoringState(status: status ?? this.status, events: events ?? this.events);
  }
}

const _maxRecentEvents = 20;

/// Drives Live Monitoring off the real `/api/v1/ws/alerts/{user_id}` feed
/// (see `fastapi_app/routers/ws.py`) — no synthetic sensor data, ever.
/// There's nothing flavor-specific to branch on here: without a signed-in
/// backend session (the mock flavor never obtains one — see
/// `AppConfig.useMockApi`) the client simply can't connect and this
/// honestly settles on "disconnected" rather than fabricating a feed.
@Riverpod(keepAlive: true)
class LiveMonitoringController extends _$LiveMonitoringController {
  RealtimeAlertsClient? _client;
  StreamSubscription<RealtimeConnectionStatus>? _statusSub;
  StreamSubscription<Map<String, dynamic>>? _eventSub;

  @override
  LiveMonitoringState build() {
    final client = RealtimeAlertsClient(
      apiClient: ref.read(apiClientProvider),
      tokenStore: ref.read(authTokenStoreProvider),
    );
    _client = client;
    _statusSub = client.status.listen((status) {
      state = state.copyWith(
        status: switch (status) {
          RealtimeConnectionStatus.connecting => MonitoringConnectionStatus.connecting,
          RealtimeConnectionStatus.connected => MonitoringConnectionStatus.connected,
          RealtimeConnectionStatus.disconnected => MonitoringConnectionStatus.disconnected,
        },
      );
    });
    _eventSub = client.events.listen((json) {
      final event = RealtimeAlertEvent.fromJson(json);
      if (event == null) return;
      state = state.copyWith(events: [event, ...state.events].take(_maxRecentEvents).toList());
    });

    ref.onDispose(() {
      _statusSub?.cancel();
      _eventSub?.cancel();
      _client?.dispose();
    });

    client.connect();
    return const LiveMonitoringState(status: MonitoringConnectionStatus.connecting, events: []);
  }

  void retry() {
    _client?.connect();
  }
}
