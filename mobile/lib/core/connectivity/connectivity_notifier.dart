import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connectivity_notifier.g.dart';

@visibleForTesting
bool isDeviceOnline(List<ConnectivityResult> results) {
  // An empty list means the platform told us nothing, not that the device is
  // definitely offline — and the two must not be collapsed. `[].any(...)` is
  // false, so the old one-liner reported "offline" whenever the plugin
  // returned nothing, which on this screen shows an offline banner and, until
  // it was fixed, filed an SOS in a queue instead of sending it.
  //
  // Unknown resolves to online. Being wrong that way costs a failed request
  // that the caller already handles; being wrong the other way costs the
  // alert.
  if (results.isEmpty) return true;
  return results.any((r) => r != ConnectivityResult.none);
}

/// Whether the device currently has *some* network interface up
/// (Wi-Fi/mobile/ethernet). This is reachability of a network, not proof
/// the SafeHer backend itself is reachable — [ApiException] still handles
/// the "online but the server rejected/timed out" case separately.
@riverpod
class ConnectivityNotifier extends _$ConnectivityNotifier {
  /// How often the current state is re-read, on top of the change stream.
  static const _recheckInterval = Duration(seconds: 10);

  @override
  Stream<bool> build() async* {
    final connectivity = Connectivity();
    // onConnectivityChanged only fires on transitions, so seed the current
    // state first — otherwise a stable connection never emits anything
    // and this provider sits in AsyncLoading forever.
    yield isDeviceOnline(await connectivity.checkConnectivity());

    // ...and because it only fires on transitions, a wrong seed was
    // permanent. If the first checkConnectivity() landed before the radio
    // had settled it returned `none`, no transition ever followed on a
    // stable connection, and the app insisted it was offline — showing the
    // banner, and queueing mutations instead of sending them — on a phone
    // with full signal. A dropped platform event did the same thing.
    //
    // Re-reading on a timer makes the state self-correcting: the worst a
    // missed or mistimed event can now cost is ten seconds of being wrong.
    // checkConnectivity() is a cheap platform call, and for an app that
    // decides whether an SOS goes out now or goes into a queue, being
    // right about this is worth a poll.
    final controller = StreamController<bool>();
    final subscriptions = <StreamSubscription<bool>>[
      connectivity.onConnectivityChanged.map(isDeviceOnline).listen(controller.add),
      Stream<void>.periodic(_recheckInterval)
          .asyncMap((_) async => isDeviceOnline(await connectivity.checkConnectivity()))
          .listen(controller.add),
    ];
    ref.onDispose(() {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
      controller.close();
    });

    // distinct() so the poll only rebuilds watchers when something actually
    // changed, rather than every ten seconds.
    yield* controller.stream.distinct();
  }
}
