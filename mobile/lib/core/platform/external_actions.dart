import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hands an action off to the device: the dialler, the SMS composer, or
/// whatever maps app the user actually has installed.
///
/// Every method returns whether the handoff succeeded so callers can tell the
/// user plainly ("No dialler available on this device") instead of tapping a
/// button that silently does nothing.
class ExternalActions {
  const ExternalActions();

  Future<bool> dial(String phoneNumber) => _launch(Uri(scheme: 'tel', path: _clean(phoneNumber)));

  Future<bool> sendSms(String phoneNumber, {String? body}) => _launch(
    Uri(
      scheme: 'sms',
      path: _clean(phoneNumber),
      queryParameters: body == null ? null : {'body': body},
    ),
  );

  /// Opens turn-by-turn navigation to a real coordinate. Uses the
  /// platform-neutral `geo:` scheme first and falls back to a Google Maps web
  /// URL, which every platform can open in a browser.
  Future<bool> navigateTo({required double latitude, required double longitude, String? label}) async {
    final encodedLabel = label == null ? '' : '($label)';
    final geoUri = Uri.parse('geo:$latitude,$longitude?q=$latitude,$longitude$encodedLabel');
    if (await _launch(geoUri)) return true;

    return _launch(
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude'),
    );
  }

  /// Opens a plain map view of a coordinate (no route).
  Future<bool> showOnMap({required double latitude, required double longitude}) => _launch(
    Uri.parse('https://www.google.com/maps/search/?api=1&query=$latitude,$longitude'),
  );

  static String _clean(String phoneNumber) => phoneNumber.replaceAll(RegExp(r'[^\d+*#]'), '');

  Future<bool> _launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('ExternalActions could not launch $uri: $error');
      return false;
    }
  }
}
