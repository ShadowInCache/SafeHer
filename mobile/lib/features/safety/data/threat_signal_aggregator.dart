import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';

/// One modality's most recent word, and when it said it.
@immutable
class TimedSignal {
  const TimedSignal({required this.value, required this.at, this.label});

  final double value;
  final DateTime at;

  /// What the modality thought it was — `knife`, `distress`, `FALL`. Carried
  /// for the incident record only; the score is [value].
  final String? label;

  bool isFresh(DateTime now, Duration maxAge) =>
      now.difference(at) <= maxAge;
}

/// Collects the three signals and reports them together.
///
/// ## Why staleness is not zero
///
/// The backend's contract is explicit that a missing modality must arrive as
/// `null` and never as `0.0`: a zero claims the sensor looked and saw calm,
/// which with no camera attached would cap the achievable score at 0.75 and
/// quietly disable the automatic alarm. That rule only holds if this class
/// enforces it, so a signal older than [maxAge] is dropped rather than sent —
/// the glasses that disconnected two minutes ago are not reporting calm, they
/// are not reporting.
///
/// ## Why it batches
///
/// Weapon inference produces a score five times a second and the recogniser
/// produces one per utterance. Posting each would be hundreds of requests a
/// minute to say almost the same thing. [postInterval] collapses them into one
/// call carrying the latest of each — the fusion engine smooths over time
/// anyway, so a faster feed would buy it nothing it does not already compute.
class ThreatSignalAggregator {
  ThreatSignalAggregator({
    required ApiClient apiClient,
    this.postInterval = const Duration(seconds: 1),
    this.maxAge = const Duration(seconds: 10),
    DateTime Function()? clock,
  })  : _apiClient = apiClient,
        _now = clock ?? DateTime.now;

  final ApiClient _apiClient;
  final Duration postInterval;
  final Duration maxAge;
  final DateTime Function() _now;

  TimedSignal? _glove;
  TimedSignal? _audio;
  TimedSignal? _weapon;

  Timer? _timer;
  bool _posting = false;
  bool _armed = false;

  /// Set by tests and by the web build, where inference is server-side.
  @visibleForTesting
  int postAttempts = 0;

  void reportGlove(double value, {String? label}) =>
      _glove = TimedSignal(value: value, at: _now(), label: label);

  void reportAudio(double value, {String? label}) =>
      _audio = TimedSignal(value: value, at: _now(), label: label);

  void reportWeapon(double value, {String? label}) =>
      _weapon = TimedSignal(value: value, at: _now(), label: label);

  bool get isArmed => _armed;

  void arm() {
    if (_armed) return;
    _armed = true;
    _timer = Timer.periodic(postInterval, (_) => unawaited(flush()));
  }

  /// Stops posting and forgets every signal.
  ///
  /// Clearing matters as much as stopping: re-arming an hour later must not
  /// begin by reporting the readings from the end of the last journey as if
  /// they were current.
  void disarm() {
    _armed = false;
    _timer?.cancel();
    _timer = null;
    _glove = null;
    _audio = null;
    _weapon = null;
  }

  /// The payload for the current instant, or null when nothing is fresh.
  @visibleForTesting
  Map<String, dynamic>? buildPayload() {
    final now = _now();
    final glove = _fresh(_glove, now);
    final audio = _fresh(_audio, now);
    final weapon = _fresh(_weapon, now);

    if (glove == null && audio == null && weapon == null) return null;

    return <String, dynamic>{
      // The wire names predate the three-signal architecture and are kept so
      // the API does not break: motion is the glove, vision is the weapon
      // detector, audio is the phrase classifier.
      if (glove != null) 'motion_score': _round(glove.value),
      if (audio != null) 'audio_score': _round(audio.value),
      if (weapon != null) 'vision_score': _round(weapon.value),
      if (weapon != null) 'weapon_confidence': _round(weapon.value),
      if (weapon?.label != null) 'weapon_label': weapon!.label,
      'timestamp': now.toUtc().toIso8601String(),
    };
  }

  /// Sends one reading if there is anything fresh to send.
  Future<void> flush() async {
    if (!_armed || _posting) return;

    final payload = buildPayload();
    if (payload == null) return;

    _posting = true;
    postAttempts++;
    try {
      await _apiClient.dio.post('/alerts/analyze', data: payload);
    } on DioException catch (_) {
      // The alarm this feeds is the server's to raise, and a dropped reading
      // is one the next tick replaces a second later. Retrying would build a
      // queue of readings that were true when they were taken and are not now.
    } finally {
      _posting = false;
    }
  }

  TimedSignal? _fresh(TimedSignal? signal, DateTime now) =>
      (signal != null && signal.isFresh(now, maxAge)) ? signal : null;

  static double _round(double value) =>
      (value.clamp(0.0, 1.0) * 1000).round() / 1000;

  void dispose() => disarm();
}
