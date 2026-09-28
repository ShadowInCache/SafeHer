import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Holds Android's `WifiManager.MulticastLock` while an mDNS query runs.
///
/// Android's Wi-Fi chip drops multicast packets not addressed to the phone
/// unless this lock is held. The query leaves the device, the camera answers,
/// and the answer is discarded below Dart — so `safeher-glasses.local` times
/// out on a phone that streams video from the same camera's IP address
/// perfectly well. `multicast_dns` does not take the lock itself.
///
/// Every failure here is non-fatal by design. A phone with no Wi-Fi service,
/// an emulator, iOS (which resolves `.local` natively and has no such lock)
/// and the web build all end up doing nothing, and the lookup still runs —
/// on a network that does not filter multicast it succeeds without the lock.
/// Refusing to resolve because the lock could not be taken would turn a
/// working setup into a broken one.
class MulticastLock {
  const MulticastLock({MethodChannel channel = _defaultChannel}) : _channel = channel;

  static const _defaultChannel = MethodChannel('io.github.akshayag.safeher/multicast');

  final MethodChannel _channel;

  /// Android only. iOS's mDNSResponder needs no lock, and a browser cannot
  /// send multicast at all, so asking there would only log a missing plugin.
  static bool get _isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Runs [body] with the lock held, releasing it however [body] ends.
  ///
  /// Reference counted natively, so two overlapping resolves — pairing and a
  /// stream reconnect — do not release each other's lock. Held only around the
  /// query: the lock defeats a power optimisation, so holding it for the life
  /// of the app would cost battery on a phone that may be needed in an
  /// emergency.
  Future<T> hold<T>(Future<T> Function() body) async {
    final acquired = await acquire();
    try {
      return await body();
    } finally {
      if (acquired) await release();
    }
  }

  /// Whether the lock is now held. `false` means carry on without it.
  Future<bool> acquire() async {
    if (!_isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('acquire') ?? false;
    } on MissingPluginException {
      // An older build of the native side, or a unit-test engine.
      return false;
    } on PlatformException catch (error) {
      if (kDebugMode) debugPrint('multicast lock unavailable: ${error.message}');
      return false;
    }
  }

  Future<void> release() async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod<void>('release');
    } on MissingPluginException {
      // Nothing was acquired.
    } on PlatformException catch (error) {
      if (kDebugMode) debugPrint('multicast lock release failed: ${error.message}');
    }
  }
}
