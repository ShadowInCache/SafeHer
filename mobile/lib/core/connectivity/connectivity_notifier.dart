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
  @override
  Stream<bool> build() async* {
    final connectivity = Connectivity();
    // onConnectivityChanged only fires on transitions, so seed the current
    // state first — otherwise a stable connection never emits anything
    // and this provider sits in AsyncLoading forever.
    yield isDeviceOnline(await connectivity.checkConnectivity());
    yield* connectivity.onConnectivityChanged.map(isDeviceOnline);
  }
}
