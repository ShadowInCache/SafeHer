import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../connectivity/connectivity_notifier.dart';
import '../di/injection.dart';
import 'offline_queue_box.dart';
import 'offline_queue_service.dart';

part 'offline_queue_providers.g.dart';

@Riverpod(keepAlive: true)
OfflineQueueService offlineQueueService(Ref ref) {
  return OfflineQueueService(getIt<OfflineQueueBox>());
}

/// Drains the offline queue whenever there is any reason to think it might
/// now succeed.
///
/// **Why this is not just an offline→online listener.** It used to be, and
/// that left queued emergency alerts stranded indefinitely. An alert reaches
/// the queue when a *request* fails, and the most common way for that to
/// happen is a request that timed out while the phone had a perfectly good
/// connection — a sleeping free-tier backend, a slow fan-out, a captive
/// portal. In that case the device never goes offline, so no offline→online
/// transition ever fires, so nothing ever retried. The screen said "will send
/// when you have signal" to someone who had signal the entire time, about an
/// alert that was never going to be sent.
///
/// So there are now three triggers, and they overlap on purpose:
///
/// * **Connectivity returning** — the original one, still the fastest signal
///   when the device genuinely was offline.
/// * **The app coming back to the foreground** — covers the phone that was
///   put away and picked up again, and costs nothing when the queue is empty.
/// * **A periodic sweep** — the backstop that makes the guarantee
///   unconditional. FR-EMG-09 promises the alert is sent on reconnect; a
///   guarantee that depends on a plugin emitting an event is not one.
///
/// Draining an empty queue is a no-op, so the cost of over-triggering is a
/// method call. The cost of under-triggering is an emergency alert nobody
/// ever receives.
@Riverpod(keepAlive: true)
class OfflineQueueDrainer extends _$OfflineQueueDrainer {
  bool? _wasOnline;
  Timer? _sweep;
  _AppLifecycleWatcher? _lifecycle;

  /// Guards against two triggers firing at once — a resume that coincides
  /// with a sweep would otherwise run the same entry twice, and for
  /// `emergency.dispatch` that means two alerts to every contact.
  bool _draining = false;

  @override
  void build() {
    ref.listen(connectivityNotifierProvider, (previous, next) {
      final isOnline = next.valueOrNull;
      if (isOnline == true && _wasOnline == false) {
        unawaited(_drain());
      }
      if (isOnline != null) _wasOnline = isOnline;
    });

    // Thirty seconds: FR-EMG-09 asks for delivery within thirty seconds of
    // connectivity being restored, and this is the trigger that has to honour
    // that on its own when no event arrives.
    _sweep = Timer.periodic(const Duration(seconds: 30), (_) => unawaited(_drain()));

    _lifecycle = _AppLifecycleWatcher(onResume: () => unawaited(_drain()));
    WidgetsBinding.instance.addObserver(_lifecycle!);

    ref.onDispose(() {
      _sweep?.cancel();
      final observer = _lifecycle;
      if (observer != null) WidgetsBinding.instance.removeObserver(observer);
    });
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      await ref.read(offlineQueueServiceProvider).drain();
    } catch (_) {
      // `drain` already records per-entry failures and bounds its own
      // retries. A throw from here would only take the timer down with it.
    } finally {
      _draining = false;
    }
  }
}

/// Calls [onResume] when the app returns to the foreground.
///
/// A tiny observer rather than a full `WidgetsBindingObserver` on some
/// screen: the queue has to drain whether or not any particular screen is
/// mounted, and the alert it holds outlives the screen that created it.
class _AppLifecycleWatcher extends WidgetsBindingObserver {
  _AppLifecycleWatcher({required this.onResume});

  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
