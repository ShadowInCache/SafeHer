import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/connectivity/connectivity_notifier.dart';

/// "Unknown" must never be reported as "offline".
///
/// `_isOnline` was `results.any((r) => r != ConnectivityResult.none)`. That
/// reads correctly until the platform returns an empty list, because
/// `[].any(...)` is false — so no information became a confident "offline".
///
/// On the home screen that showed an offline banner while the phone had a
/// working connection. On the emergency screen it was worse: the dispatcher
/// queued the SOS without attempting it, and told the woman holding the phone
/// that her contacts would be alerted "when you have signal".
void main() {
  group('isDeviceOnline', () {
    test('an empty result is treated as online, not offline', () {
      // The bug, directly. The platform saying nothing is not the platform
      // saying no.
      expect(isDeviceOnline(const []), isTrue);
    });

    test('an explicit none is offline', () {
      expect(isDeviceOnline(const [ConnectivityResult.none]), isFalse);
    });

    test('wifi, mobile and ethernet are online', () {
      for (final result in [
        ConnectivityResult.wifi,
        ConnectivityResult.mobile,
        ConnectivityResult.ethernet,
      ]) {
        expect(isDeviceOnline([result]), isTrue, reason: result.name);
      }
    });

    test('a vpn counts as online', () {
      // Common on a work phone, and it is still a route to the internet.
      expect(isDeviceOnline(const [ConnectivityResult.vpn]), isTrue);
    });

    test('any live interface alongside none is still online', () {
      // Android reports several interfaces at once; one of them being down
      // does not take the device offline.
      expect(
        isDeviceOnline(const [ConnectivityResult.none, ConnectivityResult.wifi]),
        isTrue,
      );
    });
  });
}
