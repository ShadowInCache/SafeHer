import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Silences the beep Android plays when speech recognition starts and stops.
///
/// The tone is the system recognition service's, not this app's, and
/// `speech_to_text` exposes no option to suppress it. Muting the stream it
/// plays on is the only lever, and that lives on the native side — see
/// `RecognizerTonePlugin.kt`, which also documents why ring and alarm are
/// deliberately left audible.
///
/// Every failure here is non-fatal. iOS plays no such tone, the web build has
/// no streams to mute, and a phone in Do Not Disturb may refuse the volume
/// change. In all of those the monitor still listens — a beep is a far smaller
/// problem than a journey that will not arm.
class RecognizerTone {
  const RecognizerTone({MethodChannel channel = _defaultChannel}) : _channel = channel;

  static const _defaultChannel =
      MethodChannel('io.github.akshayag.safeher/recognizer_tone');

  final MethodChannel _channel;

  /// Android only: no other platform plays the tone.
  static bool get _isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether the streams are now muted. `false` means carry on with the beep.
  Future<bool> mute() async {
    if (!_isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('mute') ?? false;
    } on MissingPluginException {
      // An older build of the native side, or a unit-test engine.
      return false;
    } on PlatformException catch (error) {
      debugPrint('SafeHer: could not mute the recogniser tone: ${error.message}');
      return false;
    }
  }

  /// Restores the streams. Safe to call when nothing was muted.
  Future<void> unmute() async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod<void>('unmute');
    } on MissingPluginException {
      // Nothing was muted.
    } on PlatformException catch (error) {
      debugPrint('SafeHer: could not restore audio streams: ${error.message}');
    }
  }
}
