import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/connectivity/connectivity_notifier.dart';
import '../../../core/network/network_providers.dart';
import '../../../core/offline/offline_queue_providers.dart';
import '../domain/emergency_repository.dart';
import 'emergency_repository_mock.dart';
import 'emergency_repository_remote.dart';

part 'emergency_providers.g.dart';

@riverpod
EmergencyRepository emergencyRepository(Ref ref) {
  if (AppConfig.useMockApi) return EmergencyRepositoryMock();
  return EmergencyRepositoryRemote(apiClient: ref.watch(apiClientProvider));
}

/// Dispatches the SOS alert. If the device is offline when the countdown
/// completes, the alert is queued via [OfflineQueueService] instead of
/// being dropped, and replays automatically the next time connectivity is
/// restored — satisfying "Offline SOS: disable network → trigger →
/// re-enable → alert sent" without blocking the on-screen dispatched
/// confirmation, which still shows immediately either way (the user
/// shouldn't have to wonder whether their SOS "worked" just because
/// they're in a signal dead zone).
@Riverpod(keepAlive: true)
class EmergencyDispatchNotifier extends _$EmergencyDispatchNotifier {
  @override
  void build() {
    _registerOfflineHandler();
  }

  void _registerOfflineHandler() {
    ref.read(offlineQueueServiceProvider).registerHandler('emergency.dispatch', (payload) async {
      await ref
          .read(emergencyRepositoryProvider)
          .dispatchAlert(
            severity: payload['severity'] as String,
            summary: payload['summary'] as String,
            auto: payload['auto'] as bool,
            latitude: payload['latitude'] as double?,
            longitude: payload['longitude'] as double?,
            accuracyMeters: payload['accuracyMeters'] as double?,
          );
    });
  }

  bool get _isOffline => ref.read(connectivityNotifierProvider).valueOrNull == false;

  /// Returns true if the alert was queued for later delivery (offline)
  /// rather than sent immediately — callers don't need to change their UI
  /// based on this, it's informational only. [latitude]/[longitude] are
  /// omitted when a location fix wasn't available — see [LocationService].
  Future<bool> dispatch({
    required String severity,
    required String summary,
    required bool auto,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  }) async {
    if (_isOffline) {
      await ref.read(offlineQueueServiceProvider).enqueue('emergency.dispatch', {
        'severity': severity,
        'summary': summary,
        'auto': auto,
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
      });
      return true;
    }
    try {
      await ref
          .read(emergencyRepositoryProvider)
          .dispatchAlert(
            severity: severity,
            summary: summary,
            auto: auto,
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: accuracyMeters,
          );
    } catch (_) {
      // Reachable network but the request itself failed (timeout, 5xx,
      // etc.) — still queue it rather than silently losing the alert.
      await ref.read(offlineQueueServiceProvider).enqueue('emergency.dispatch', {
        'severity': severity,
        'summary': summary,
        'auto': auto,
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
      });
      return true;
    }
    return false;
  }
}
