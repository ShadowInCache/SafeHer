import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/local/app_preferences.dart';

part 'glasses_pairing_controller.g.dart';

enum GlassesPairingStage { idle, testing, reachable, unreachable }

/// What the glasses said when asked, and whether they answered at all.
@immutable
class GlassesPairingState {
  const GlassesPairingState({
    this.stage = GlassesPairingStage.idle,
    this.host = '',
    this.firmware,
    this.battery,
    this.error,
  });

  final GlassesPairingStage stage;

  /// The address currently saved, or the one being tested.
  final String host;

  /// Reported by `GET /status`. Absent means the glasses answered but did not
  /// say — which is different from answering zero, and is why battery is
  /// nullable rather than defaulted.
  final String? firmware;
  final int? battery;

  final String? error;

  bool get isPaired => host.isNotEmpty;
  bool get isTesting => stage == GlassesPairingStage.testing;

  GlassesPairingState copyWith({
    GlassesPairingStage? stage,
    String? host,
    String? firmware,
    int? battery,
    String? error,
    bool clearError = false,
    bool clearDetails = false,
  }) =>
      GlassesPairingState(
        stage: stage ?? this.stage,
        host: host ?? this.host,
        firmware: clearDetails ? null : (firmware ?? this.firmware),
        battery: clearDetails ? null : (battery ?? this.battery),
        error: clearError ? null : (error ?? this.error),
      );
}

/// Pairs the glasses by address, and proves the address before saving it.
///
/// ## Why this exists at all
///
/// The whole weapon-detection path — the MJPEG parser, the detector, the
/// scorer, the server fallback — was built and tested while nothing anywhere
/// called `setGlassesHost`. `glassesStreamUri` was therefore always null,
/// `ThreatPipeline` returned early, and the camera signal could never run on
/// any platform. Everything worked except the one screen that lets someone
/// type in an address.
///
/// ## Why it tests before it saves
///
/// A saved address that answers nothing is worse than no address: the app
/// would show a paired pair of glasses and report the weapon signal as
/// available while no frame ever arrived. So pairing means `GET /status`
/// returned, and nothing else counts.
@Riverpod(keepAlive: true)
class GlassesPairing extends _$GlassesPairing {
  static const defaultHost = 'safeher-glasses.local';

  /// Short on purpose. These are on the same WiFi; if they do not answer in a
  /// couple of seconds they are asleep, out of range, or on another network,
  /// and making someone wait ten seconds to learn that helps nobody.
  static const _timeout = Duration(seconds: 3);

  Dio? _client;

  @override
  GlassesPairingState build() {
    final saved = ref.watch(appPreferencesProvider).glassesHost;
    return GlassesPairingState(
      host: saved,
      stage: saved.isEmpty
          ? GlassesPairingStage.idle
          : GlassesPairingStage.reachable,
    );
  }

  /// Injected by tests; a plain client otherwise.
  ///
  /// Deliberately not the authenticated `ApiClient`: these requests go to a
  /// device on the local network, and must never carry the user's bearer token.
  @visibleForTesting
  set client(Dio value) => _client = value;

  Dio get _dio => _client ??= Dio(
        BaseOptions(connectTimeout: _timeout, receiveTimeout: _timeout),
      );

  static Uri? statusUri(String host) {
    final trimmed = host.trim();
    if (trimmed.isEmpty) return null;
    final withScheme = trimmed.startsWith('http') ? trimmed : 'http://$trimmed';
    return Uri.tryParse('$withScheme/status');
  }

  /// Asks the glasses to identify themselves, and saves the address if they do.
  Future<bool> pair(String host) async {
    final uri = statusUri(host);
    if (uri == null) {
      state = state.copyWith(
        stage: GlassesPairingStage.unreachable,
        error: 'That does not look like an address.',
      );
      return false;
    }

    state = state.copyWith(
      stage: GlassesPairingStage.testing,
      host: host.trim(),
      clearError: true,
      clearDetails: true,
    );

    try {
      final response = await _dio.getUri<Map<String, dynamic>>(uri);
      final body = response.data ?? const {};

      // A web server answering on that address is not the same as *these*
      // glasses answering. Without this check, pairing would succeed against a
      // router's admin page and the app would claim a camera it does not have.
      if (body['device'] != 'safeher-glasses') {
        state = state.copyWith(
          stage: GlassesPairingStage.unreachable,
          error: 'Something answered, but it is not a SafeHer camera.',
        );
        return false;
      }

      final battery = body['battery'];
      state = state.copyWith(
        stage: GlassesPairingStage.reachable,
        firmware: body['firmware']?.toString(),
        // An implausible zero is treated as absent, as it is for the glove's
        // heart rate: "no reading" and "flat battery" must not look alike.
        battery: (battery is num && battery > 0) ? battery.toInt() : null,
        clearError: true,
      );
      // Not `invalidateSelf()`. Rebuilding re-reads the address from
      // preferences and discards the firmware and battery just learned, which
      // is the whole point of having asked.
      await ref.read(appPreferencesProvider).setGlassesHost(host.trim());
      return true;
    } on DioException catch (error) {
      state = state.copyWith(
        stage: GlassesPairingStage.unreachable,
        error: _explain(error),
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        stage: GlassesPairingStage.unreachable,
        error: 'The camera answered with something unreadable.',
      );
      return false;
    }
  }

  /// `http://<host>/audio`, or null when no camera is paired.
  ///
  /// Separate from the stream URI because the two are consumed by different
  /// things for different reasons: video feeds the weapon detector during a
  /// journey, audio is captured only as evidence during an incident.
  Uri? get audioUri {
    final host = state.host;
    if (host.isEmpty) return null;
    final withScheme = host.startsWith('http') ? host : 'http://$host';
    return Uri.tryParse('$withScheme/audio');
  }

  Future<void> unpair() async {
    await ref.read(appPreferencesProvider).setGlassesHost('');
    state = const GlassesPairingState();
  }

  /// Plain language, and specific enough to act on.
  static String _explain(DioException error) => switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout =>
          'No answer. Check the camera is on and on this WiFi network.',
        DioExceptionType.badResponse =>
          'The camera answered with an error (${error.response?.statusCode}).',
        _ => 'Could not reach the camera at that address.',
      };
}
