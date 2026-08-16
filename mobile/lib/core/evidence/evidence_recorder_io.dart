import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'evidence_recorder.dart';

/// Native [EvidenceRecorder], backed by the `record` package.
///
/// Reached only through `platform_evidence_recorder.dart`'s conditional
/// export — it imports `dart:io`, which throws on web.
///
/// The only file in the app allowed to import `record`; everything above it
/// speaks [EvidenceRecording].
class PlatformEvidenceRecorder implements EvidenceRecorder {
  PlatformEvidenceRecorder({AudioRecorder? recorder}) : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  String? _path;
  bool _isRecording = false;

  @override
  bool get isRecording => _isRecording;

  /// AAC in an m4a container: hardware-encoded on both mobile platforms, so
  /// it costs little battery, and small enough that a minute of audio
  /// uploads over a weak connection — which is the connection an emergency
  /// tends to happen on.
  static const _config = RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 64000,
    sampleRate: 44100,
    numChannels: 1,
  );

  static const _mimeType = 'audio/mp4';

  @override
  Future<bool> isSupported() async {
    // `record` has a web implementation, but it hands back a blob URL rather
    // than a file and the surrounding upload path is built for bytes off
    // disk. Rather than half-support it, web reports unsupported and the UI
    // says so — the same call made for BLE pairing.
    if (kIsWeb) return false;
    try {
      return await _recorder.isEncoderSupported(AudioEncoder.aacLc);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  @override
  Future<void> start() async {
    if (_isRecording) return;

    if (!await isSupported()) {
      throw const EvidenceRecorderException(EvidenceRecorderFailure.unsupported);
    }

    final status = await Permission.microphone.status;
    if (status.isPermanentlyDenied) {
      throw const EvidenceRecorderException(
        EvidenceRecorderFailure.permissionPermanentlyDenied,
      );
    }
    if (!status.isGranted && !await requestPermission()) {
      throw const EvidenceRecorderException(EvidenceRecorderFailure.permissionDenied);
    }

    try {
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/safeher-evidence-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(_config, path: path);
      _path = path;
      _isRecording = true;
    } catch (error) {
      _isRecording = false;
      throw EvidenceRecorderException(EvidenceRecorderFailure.failed, '$error');
    }
  }

  @override
  Future<EvidenceRecording?> stop() async {
    if (!_isRecording) return null;
    _isRecording = false;

    String? path;
    try {
      path = await _recorder.stop() ?? _path;
    } catch (_) {
      path = _path;
    }
    _path = null;
    if (path == null) return null;

    final file = File(path);
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return EvidenceRecording(bytes: bytes, mimeType: _mimeType);
    } catch (_) {
      return null;
    } finally {
      // Deleted whether or not the read succeeded. The upload is the only
      // copy that should outlive the emergency.
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Best effort: a leftover temp file is not worth failing an alert.
      }
    }
  }

  @override
  Future<void> cancel() async {
    if (!_isRecording) return;
    _isRecording = false;
    try {
      await _recorder.stop();
    } catch (_) {
      // Ignored: we are discarding this recording anyway.
    }
    final path = _path;
    _path = null;
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort, as above.
    }
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }
}
