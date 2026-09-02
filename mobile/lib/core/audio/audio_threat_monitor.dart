import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

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
    Duration listenFor = const Duration(seconds: 20),
    Duration pauseFor = const Duration(seconds: 4),
    Duration restartDelay = const Duration(milliseconds: 400),
  })  : _classifier = classifier,
        _speech = speech ?? SpeechToText(),
        _listenFor = listenFor,
        _pauseFor = pauseFor,
        _restartDelay = restartDelay;

  final ThreatPhraseClassifier _classifier;
  final SpeechToText _speech;
  final Duration _listenFor;
  final Duration _pauseFor;
  final Duration _restartDelay;

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

    if (!_initialised) {
      try {
        _initialised = await _speech.initialize(
          onError: (_) => _scheduleRestart(),
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
    _publish(AudioMonitorStatus.idle);
  }

  Future<void> _listenOnce() async {
    if (!_wantsToListen || _disposed || _speech.isListening) return;
    try {
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          partialResults: false,
          cancelOnError: false,
          listenFor: _listenFor,
          pauseFor: _pauseFor,
        ),
        onResult: (result) {
          if (!result.finalResult) return;
          _score(result.recognizedWords);
        },
      );
    } catch (_) {
      _scheduleRestart();
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
    _restartTimer = Timer(_restartDelay, _listenOnce);
  }

  Future<void> dispose() async {
    await stop();
    _disposed = true;
    await _readings.close();
    await _statuses.close();
  }
}
