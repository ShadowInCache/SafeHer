import 'package:safeher_app/core/background/safety_foreground_service.dart';

/// A [SafetyForegroundService] that records what was asked of it.
///
/// The real one needs an Android activity, so the decision of *when* to watch
/// is tested against this and the plugin call is not tested at all — the same
/// split the BLE layer already uses. [startSucceeds] exists because a refused
/// service is not an edge case here: notification permission can be denied and
/// OEMs kill background work routinely, and the app has to describe that state
/// truthfully rather than assume the request worked.
class FakeForegroundService implements SafetyForegroundService {
  FakeForegroundService({this.startSucceeds = true});

  /// Whether [start] should report the service as actually running.
  bool startSucceeds;

  bool running = false;
  int startCalls = 0;
  int stopCalls = 0;
  int bringToForegroundCalls = 0;

  /// The reasons passed to the most recent [start].
  ///
  /// Recorded because the reasons decide the Android service types, and a
  /// journey whose microphone type was never declared is the defect this fake
  /// is used to pin.
  Set<WatchReason> lastReasons = const {};

  /// Every set of reasons [start] has been called with, in order.
  final List<Set<WatchReason>> startedWith = [];

  @override
  Future<bool> isRunning() async => running;

  @override
  Future<bool> start({required Set<WatchReason> reasons}) async {
    startCalls++;
    lastReasons = Set.of(reasons);
    startedWith.add(Set.of(reasons));
    running = startSucceeds;
    return running;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    running = false;
  }

  @override
  Future<void> bringToForeground() async {
    bringToForegroundCalls++;
  }
}
