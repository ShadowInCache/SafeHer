import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

import 'voice_command.dart';

/// Thin wrapper over on-device speech recognition.
///
/// Privacy properties this deliberately holds to:
///   * listening only ever starts from an explicit user action;
///   * recognised text is matched against [VoiceCommandMatcher] and then
///     dropped — never stored, never uploaded, never attached to an incident;
///   * a single utterance is captured per session, so the mic doesn't sit
///     open indefinitely.
class VoiceCommandService {
  VoiceCommandService({SpeechToText? speech, VoiceCommandMatcher matcher = const VoiceCommandMatcher()})
    : _speech = speech ?? SpeechToText(),
      _matcher = matcher;

  final SpeechToText _speech;
  final VoiceCommandMatcher _matcher;

  bool _available = false;
  bool get isListening => _speech.isListening;

  /// Returns false when the microphone permission was refused or the platform
  /// has no recogniser — callers must show that state rather than pretending
  /// to listen.
  Future<bool> initialise() async {
    if (_available) return true;
    try {
      _available = await _speech.initialize(
        onError: (_) {},
        onStatus: (_) {},
      );
    } catch (_) {
      _available = false;
    }
    return _available;
  }

  /// Listens for one utterance and resolves with the matched command, the
  /// raw transcript, or a null command when nothing matched.
  Future<VoiceCommandResult> listenOnce({
    Duration listenFor = const Duration(seconds: 6),
  }) async {
    if (!await initialise()) {
      return const VoiceCommandResult(status: VoiceCommandStatus.unavailable);
    }

    final completer = Completer<VoiceCommandResult>();

    void finish(VoiceCommandResult result) {
      if (!completer.isCompleted) completer.complete(result);
    }

    try {
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          partialResults: false,
          cancelOnError: true,
          listenFor: listenFor,
        ),
        onResult: (result) {
          if (!result.finalResult) return;
          final transcript = result.recognizedWords;
          finish(
            VoiceCommandResult(
              status: VoiceCommandStatus.completed,
              transcript: transcript,
              command: _matcher.match(transcript),
            ),
          );
        },
      );
    } catch (_) {
      return const VoiceCommandResult(status: VoiceCommandStatus.unavailable);
    }

    // Nothing intelligible arrived before the window closed.
    Timer(listenFor + const Duration(seconds: 1), () {
      finish(const VoiceCommandResult(status: VoiceCommandStatus.completed));
    });

    return completer.future;
  }

  Future<void> stop() async {
    if (_speech.isListening) await _speech.stop();
  }
}

enum VoiceCommandStatus { completed, unavailable }

class VoiceCommandResult {
  const VoiceCommandResult({required this.status, this.transcript, this.command});

  final VoiceCommandStatus status;
  final String? transcript;
  final VoiceCommand? command;

  bool get isUnavailable => status == VoiceCommandStatus.unavailable;
  bool get heardNothing => status == VoiceCommandStatus.completed && (transcript ?? '').isEmpty;
  bool get notRecognised =>
      status == VoiceCommandStatus.completed && command == null && (transcript ?? '').isNotEmpty;
}
