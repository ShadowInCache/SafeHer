import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'recognizer_tone.dart';
import 'threat_phrase_classifier.dart';

/// One utterance, scored.
///
/// **The transcript is not here, and that is deliberate.** It is classified and
/// dropped inside the monitor. Carrying the recognised words out of this file
/// would put them in provider state, in error logs and eventually in an
/// incident record, and the promise this feature is built on is that what she
/// says is turned into a number on her own phone and then forgotten.
@immutable
class AudioThreatReading {
  const AudioThreatReading({
    required this.score,
    required this.label,
    required this.heardAt,
  });

  /// `P(threat) + P(distress)` — the number the fusion engine consumes.
  final double score;

  /// `threat`, `distress` or `normal`, for describing the incident afterwards.
  final String label;

  final DateTime heardAt;

  bool get isElevated => score >= 0.5;

  @override
  String toString() =>
      'AudioThreatReading($label, ${score.toStringAsFixed(2)}, $heardAt)';
}

/// Why the monitor is not listening, when it is not.
enum AudioMonitorStatus {
  /// Not asked to listen.
  idle,

  /// Listening, or between two listening sessions.
  listening,

  /// The microphone was refused, or the platform has no recogniser.
  ///
  /// Distinct from [idle] because the UI must be able to say "this is off"
  /// differently from "this cannot be turned on". A safety feature that looks
  /// armed and is not is the failure this codebase keeps having to fix.
  unavailable,
}

/// Listens while armed, scores what it hears, and forgets the words.
///
/// ## Why sessions restart instead of one long listen
///
/// Android's recogniser ends a session on a pause and caps how long one can
/// run. There is no continuous mode to ask for, so continuity is made of many
/// short sessions restarted back to back. The restart is deliberately delayed
/// by [_restartDelay]: without it, a platform that refuses immediately turns
/// this into a spin loop that flattens the battery in minutes while appearing
/// to work.
///
/// ## What it does not do
///
/// It does not decide anything. It emits scores; the aggregator decides
/// whether they still count, and the fusion engine decides what they mean
/// together with the glove and the camera. A single frightened sentence is not
/// an emergency on its own, and nothing here is allowed to think it is.
class AudioThreatMonitor {
  AudioThreatMonitor({
    required ThreatPhraseClassifier classifier,
    SpeechToText? speech,
    RecognizerTone tone = const RecognizerTone(),
    Duration listenFor = const Duration(seconds: 20),
    Duration pauseFor = const Duration(seconds: 4),
    Duration restartDelay = const Duration(milliseconds: 400),
    Duration maxRestartDelay = const Duration(seconds: 30),
    bool preferOnDevice = true,
  })  : _classifier = classifier,
        _maxRestartDelay = maxRestartDelay,
        _preferOnDevice = preferOnDevice,
        _speech = speech ?? SpeechToText(),
        _tone = tone,
        _listenFor = listenFor,
        _pauseFor = pauseFor,
        _restartDelay = restartDelay;

  final ThreatPhraseClassifier _classifier;
  final SpeechToText _speech;
  final RecognizerTone _tone;
  final Duration _listenFor;
  final Duration _pauseFor;
  final Duration _restartDelay;

  /// Ceiling for the exponential backoff below.
  final Duration _maxRestartDelay;

  /// Whether to ask for on-device recognition.
  ///
  /// Measured on a Samsung SM M166P, 17 October: with network recognition the
  /// platform logged `ONLINE_NO_PROGRESS` 131 times and never returned a
  /// transcript, because the phone's connection was too unreliable to stream
  /// audio. A safety feature that stops listening when the network wobbles is
  /// not much of a safety feature, so on-device is asked for first.
  ///
  /// It is a preference, not a requirement: `onDevice: true` makes the
  /// platform *fail* rather than fall back, so after
  /// [_onDeviceAttemptsBeforeFallback] consecutive failures this flips to the
  /// permissive mode for the rest of the session.
  bool _preferOnDevice;

  static const _onDeviceAttemptsBeforeFallback = 3;

  /// Consecutive failed listen attempts, driving the backoff.
  int _failures = 0;

  final _readings = StreamController<AudioThreatReading>.broadcast();
  final _statuses = StreamController<AudioMonitorStatus>.broadcast();

  bool _wantsToListen = false;
  bool _initialised = false;
  bool _disposed = false;
  Timer? _restartTimer;
  AudioMonitorStatus _status = AudioMonitorStatus.idle;

  Stream<AudioThreatReading> get readings => _readings.stream;
  Stream<AudioMonitorStatus> get statuses => _statuses.stream;
  AudioMonitorStatus get status => _status;

  void _publish(AudioMonitorStatus next) {
    if (_status == next || _disposed) return;
    _status = next;
    _statuses.add(next);
  }

  /// Begins listening. Safe to call when already listening.
  ///
  /// Returns false when the platform will not let this run, so the caller can
  /// say so rather than showing an armed state over a dead microphone.
  Future<bool> start() async {
    if (_disposed) return false;
    _wantsToListen = true;
    _failures = 0;

    if (!_initialised) {
      try {
        _initialised = await _speech.initialize(
          onError: (error) {
            // Previously `(_) => _scheduleRestart()`, which threw the reason
            // away. The monitor then cycled the microphone roughly twice a
            // second for a whole journey while reporting nothing, and there
            // was no way to see why from outside the device.
            _noteFailure('$error');
            _scheduleRestart();
          },
          onStatus: (_) => _scheduleRestart(),
        );
      } catch (_) {
        _initialised = false;
      }
    }
    if (!_initialised) {
      _wantsToListen = false;
      _publish(AudioMonitorStatus.unavailable);
      return false;
    }

    // Muted for the whole listening period rather than around each session.
    // Per-session muting would still duck the audio every few seconds as
    // sessions restart, which is its own kind of irritating.
    await _tone.mute();

    _publish(AudioMonitorStatus.listening);
    await _listenOnce();
    return true;
  }

  Future<void> stop() async {
    _wantsToListen = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    try {
      if (_speech.isListening) await _speech.stop();
    } catch (_) {
      // A recogniser that will not stop cleanly must not take the caller down
      // with it — `stop` is what runs when a journey ends or the app closes.
    }
    // Outside the try above on purpose: the phone must not be left silent
    // because the recogniser failed to stop cleanly.
    await _tone.unmute();
    _publish(AudioMonitorStatus.idle);
  }

  Future<void> _listenOnce() async {
    if (!_wantsToListen || _disposed || _speech.isListening) return;

    // Clear any session the platform is still holding before asking for a new
    // one.
    //
    // Measured on a Samsung SM M166P: after `error_client` the plugin reports
    // `isListening == false`, but the platform recogniser has not released
    // the session, so the next `listen()` comes straight back as `error_busy`
    // -- twice in a row, every time. Cancelling first makes the retry a real
    // retry instead of a request the service was always going to refuse.
    if (_failures > 0) {
      try {
        await _speech.cancel();
      } catch (_) {
        // Nothing to cancel, or the platform refused. Either way the listen
        // attempt below is no worse off for having asked.
      }
    }

    try {
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          partialResults: false,
          cancelOnError: false,
          onDevice: _preferOnDevice,
          listenFor: _listenFor,
          pauseFor: _pauseFor,
        ),
        onResult: (result) {
          if (!result.finalResult) return;
          // A transcript means the recogniser is healthy: drop the backoff so
          // the next ordinary silence is not punished with a long wait.
          _failures = 0;
          _score(result.recognizedWords);
        },
      );
    } catch (error) {
      _noteFailure('$error');
      _scheduleRestart();
    }
  }

  /// Records a failed attempt and reports it, sparingly.
  ///
  /// Logged for the first few and then every tenth, because the failure mode
  /// this exists to expose produces hundreds of them a minute and a log line
  /// per failure would bury everything else in the capture.
  void _noteFailure(String reason) {
    _failures++;
    if (_failures <= 3 || _failures % 10 == 0) {
      debugPrint('SafeHer: speech recogniser failed (#$_failures'
          '${_preferOnDevice ? ", on-device" : ", network"}): $reason');
    }
    if (_preferOnDevice && _failures >= _onDeviceAttemptsBeforeFallback) {
      _preferOnDevice = false;
      debugPrint('SafeHer: on-device recognition unavailable, '
          'falling back to the platform default');
    }
  }

  /// Classifies one utterance and drops the words.
  void _score(String transcript) {
    if (_disposed) return;
    if (transcript.trim().isEmpty) return;

    final verdict = _classifier.classify(transcript);
    _readings.add(
      AudioThreatReading(
        score: verdict.elevated,
        label: verdict.label,
        heardAt: DateTime.now(),
      ),
    );
    // `transcript` and `verdict.probabilities` go out of scope here and are
    // never written anywhere. That is the whole privacy story for this feature.
  }

  void _scheduleRestart() {
    if (!_wantsToListen || _disposed) return;
    _restartTimer?.cancel();
    // Exponential backoff. A flat 400 ms retry meant ~2.5 attempts a second;
    // Android's recognition service caps outstanding requests and began
    // refusing this app outright -- "#startListening received when the
    // service's capacity is full - ignoring this call", 256 times in one
    // journey. Backing off lets the service recover instead of being hammered.
    final shift = _failures.clamp(0, 16);
    final delayMs = (_restartDelay.inMilliseconds * (1 << shift))
        .clamp(_restartDelay.inMilliseconds, _maxRestartDelay.inMilliseconds);
    _restartTimer = Timer(Duration(milliseconds: delayMs), _listenOnce);
  }

  Future<void> dispose() async {
    await stop();
    _disposed = true;
    await _readings.close();
    await _statuses.close();
  }
}
