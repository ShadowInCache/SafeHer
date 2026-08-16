import 'package:flutter/foundation.dart';

/// A finished recording, held in memory on its way to the server.
///
/// Bytes rather than a file path: the local copy is deleted as soon as it
/// has been read. A recording of an assault sitting in the device's temp
/// directory is one file-manager app away from the person it was recorded
/// about.
@immutable
class EvidenceRecording {
  const EvidenceRecording({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;

  int get sizeBytes => bytes.length;
}

/// Why a recording could not be made. Kept as a small enum rather than a
/// message so the UI can decide what to say and whether to offer settings.
enum EvidenceRecorderFailure {
  /// The user has not granted microphone access.
  permissionDenied,

  /// Denied permanently — only the system settings screen can undo it.
  permissionPermanentlyDenied,

  /// This platform cannot record (web, or a device with no microphone).
  unsupported,

  /// The recorder started but produced nothing usable.
  failed,
}

class EvidenceRecorderException implements Exception {
  const EvidenceRecorderException(this.reason, [this.detail]);

  final EvidenceRecorderFailure reason;
  final String? detail;

  @override
  String toString() => 'EvidenceRecorderException($reason)${detail == null ? '' : ': $detail'}';
}

/// Captures audio evidence during an emergency (SRS FR-EMG-06).
///
/// Audio only, deliberately. Video needs a camera pointed at something
/// useful, which a phone in a pocket or a bag is not, and it costs battery
/// and upload time an emergency cannot spare. Audio records whatever is
/// happening regardless of where the phone is — which is the situation this
/// feature exists for.
abstract class EvidenceRecorder {
  /// Whether this platform can record at all.
  Future<bool> isSupported();

  /// True when microphone access has already been granted.
  Future<bool> hasPermission();

  /// Prompts for microphone access, returning whether it was granted.
  Future<bool> requestPermission();

  /// Begins recording. Throws [EvidenceRecorderException] if it cannot.
  Future<void> start();

  /// Stops and returns what was captured, deleting the local copy.
  ///
  /// Returns null when nothing was recorded — the caller treats that as "no
  /// evidence", never as a failure worth blocking the alert over.
  Future<EvidenceRecording?> stop();

  /// Abandons an in-progress recording without returning it.
  Future<void> cancel();

  bool get isRecording;

  Future<void> dispose();
}
