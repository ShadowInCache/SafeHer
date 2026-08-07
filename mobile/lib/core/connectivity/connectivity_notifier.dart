import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connectivity_notifier.g.dart';

bool _isOnline(List<ConnectivityResult> results) => results.any((r) => r != ConnectivityResult.none);

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
    yield _isOnline(await connectivity.checkConnectivity());
    yield* connectivity.onConnectivityChanged.map(_isOnline);
  }
}
