import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';

/// Whether to print each reading and the fusion engine's reply to the log.
///
/// Deliberately on by default and *not* gated on `kDebugMode`: the thing worth
/// checking is a release build on a real phone with the real wearables, which
/// is exactly where `kDebugMode` logging disappears. One line per second, and
/// only while a journey is armed.
///
/// Turn it off with `--dart-define=SAFEHER_LOG_SIGNALS=false`.
const bool kLogThreatSignals =
    bool.fromEnvironment('SAFEHER_LOG_SIGNALS', defaultValue: true);

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

  /// Forgets the weapon signal, so the next payload omits it entirely.
  ///
  /// Needed because the camera no longer runs for the whole journey: it is
  /// opened when the microphone or the glove suggests something is happening,
  /// and closed again afterwards. Closing it must leave the weapon signal
  /// **absent**, not zero.
  ///
  /// The difference decides whether an alarm can be raised at all. A zero says
  /// the camera looked and saw calm, and the fusion engine weighs it at 0.40 —
  /// which with a quiet camera caps the achievable score below the threshold
  /// and silently disables the automatic alarm the audio and the glove should
  /// have produced between them. Absent is the truth: nothing looked.
  void retractWeapon() => _weapon = null;

  /// Forgets the glove signal, so the next payload omits it entirely.
  ///
  /// Used when the glove classifies `NORMAL`, which is **not** a reading of
  /// 0.0 — it is the absence of one.
  ///
  /// The glove measures motion. `NORMAL` means "no threatening motion
  /// pattern", which is the absence of motion evidence, not evidence that
  /// nothing is wrong. Reporting it as a score told the fusion engine the
  /// opposite: a sensor that looked and found calm, weighted at 0.25.
  ///
  /// Measured against the live engine, that inverted the feature. A knife
  /// detected at full confidence scores 1.000 and raises the alarm with no
  /// glove paired; with a glove reporting `NORMAL` it scored **0.615** and
  /// raised nothing. A scream at 0.90 fell from 0.900 to 0.525. **Wearing the
  /// glove made her less protected than not wearing it** — and in the likeliest
  /// scenario of all, because holding still is what people do when a weapon is
  /// pointed at them, so `NORMAL` is exactly what the glove reports at the
  /// moment it matters most.
  ///
  /// `SHAKING` and `TWISTING` still report at 0.3: those are real low readings
  /// about motion that actually happened. Only "nothing to say" is withheld.
  void retractGlove() => _glove = null;

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
    if (payload == null) {
      if (kLogThreatSignals) {
        debugPrint('SafeHer: analyze -> nothing fresh to send');
      }
      return;
    }

    _posting = true;
    postAttempts++;
    try {
      final response = await _apiClient.dio.post('/alerts/analyze', data: payload);
      if (kLogThreatSignals) _logExchange(payload, response.data);
    } on DioException catch (error) {
      if (kLogThreatSignals) {
        debugPrint('SafeHer: analyze -> ${_describe(payload)} | FAILED '
            '(${error.response?.statusCode ?? error.type.name})');
      }
      // The alarm this feeds is the server's to raise, and a dropped reading
      // is one the next tick replaces a second later. Retrying would build a
      // queue of readings that were true when they were taken and are not now.
    } finally {
      _posting = false;
    }
  }

  /// One line per reading: what we sent, and what the fusion engine made of it.
  ///
  /// `modalities_used` is the only authoritative answer to "did this signal
  /// actually reach the engine" — it names the signals the verdict rests on.
  /// Printing it beside the payload makes a dropped signal obvious: it is in
  /// the left half and missing from the right.
  void _logExchange(Map<String, dynamic> payload, Object? body) {
    final sent = _describe(payload);
    if (body is! Map) {
      debugPrint('SafeHer: analyze -> $sent | (no verdict in response)');
      return;
    }
    final score = body['fused_score'];
    final used = (body['modalities_used'] as List?)?.join(',') ?? 'none';
    final level = (body['live_score'] as Map?)?['level'] ?? '?';
    // Present and non-null only when the server actually dispatched.
    final sos = body['auto_sos'] == null ? '' : '  ** AUTO-SOS **';
    debugPrint('SafeHer: analyze -> $sent => fused $score [$used] $level$sos');
  }

  static String _describe(Map<String, dynamic> payload) {
    String show(String key, String name) {
      final value = payload[key];
      // "--" is the point of this line: it distinguishes a signal that is
      // absent from one reporting a low score.
      return value == null ? '$name --' : '$name $value';
    }

    return '${show('motion_score', 'glove')} | '
        '${show('audio_score', 'audio')} | '
        '${show('vision_score', 'weapon')}';
  }

  TimedSignal? _fresh(TimedSignal? signal, DateTime now) =>
      (signal != null && signal.isFresh(now, maxAge)) ? signal : null;

  static double _round(double value) =>
      (value.clamp(0.0, 1.0) * 1000).round() / 1000;

  void dispose() => disarm();
}
