import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/connectivity/connectivity_notifier.dart';
import '../../../core/network/network_providers.dart';
import '../../../core/offline/offline_queue_providers.dart';
import '../../../core/evidence/evidence_recorder.dart';
import '../../../core/evidence/platform_evidence_recorder.dart';
import '../domain/emergency_repository.dart';
import '../domain/evidence_repository.dart';
import 'emergency_repository_mock.dart';
import 'emergency_repository_remote.dart';
import 'evidence_repository_mock.dart';
import 'evidence_repository_remote.dart';

part 'emergency_providers.g.dart';

@riverpod
EmergencyRepository emergencyRepository(Ref ref) {
  if (AppConfig.useMockApi) return EmergencyRepositoryMock();
  return EmergencyRepositoryRemote(apiClient: ref.watch(apiClientProvider));
}

@riverpod
EvidenceRepository evidenceRepository(Ref ref) {
  if (AppConfig.useMockApi) return EvidenceRepositoryMock();
  return EvidenceRepositoryRemote(apiClient: ref.watch(apiClientProvider));
}

/// One recorder for the app: it owns a platform resource (the microphone)
/// that must not be opened twice.
@Riverpod(keepAlive: true)
EvidenceRecorder evidenceRecorder(Ref ref) {
  final recorder = PlatformEvidenceRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
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

  /// Sends the alert and reports what happened to it.
  ///
  /// Callers **do** need this result: the Emergency screen shows which
  /// contacts were reached, and it used to animate every contact green on a
  /// timer regardless of whether anything was sent. On a safety screen that
  /// is not a cosmetic bug — it tells a woman in danger that her sister
  /// knows, when nothing left the phone.
  ///
  /// [latitude]/[longitude] are omitted when a location fix wasn't
  /// available — see [LocationService].
  Future<DispatchResult> dispatch({
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
      return const DispatchResult.queued();
    }
    try {
      final outcome = await ref
          .read(emergencyRepositoryProvider)
          .dispatchAlert(
            severity: severity,
            summary: summary,
            auto: auto,
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: accuracyMeters,
          );
      return DispatchResult.sent(outcome);
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
      return const DispatchResult.queued();
    }
  }
}

/// What became of a dispatch attempt.
class DispatchResult {
  const DispatchResult.sent(this.outcome) : isQueued = false;

  /// The device was offline, or the request failed and the alert was put on
  /// the offline queue to replay. Nothing has reached anyone *yet* — which
  /// the UI must show as pending, never as delivered.
  const DispatchResult.queued() : isQueued = true, outcome = const DispatchOutcome.queued();

  final bool isQueued;
  final DispatchOutcome outcome;
}
