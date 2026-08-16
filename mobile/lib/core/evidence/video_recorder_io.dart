import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'evidence_recorder.dart';
import 'video_recorder.dart';

/// Native [VideoEvidenceRecorder], backed by the `camera` package.
///
/// Reached only through `platform_video_recorder.dart`'s conditional export
/// — it imports `dart:io`, which throws on web.
///
/// The only file in the app allowed to import `camera`; everything above it
/// speaks [EvidenceRecording].
class PlatformVideoRecorder implements VideoEvidenceRecorder {
  PlatformVideoRecorder({List<CameraDescription>? cameras}) : _injectedCameras = cameras;

  final List<CameraDescription>? _injectedCameras;

  CameraController? _controller;
  bool _isRecording = false;

  @override
  bool get isRecording => _isRecording;

  /// Medium rather than max, and the ceiling is not arbitrary: the server
  /// rejects evidence above `EVIDENCE_MAX_SIZE_BYTES`, 25 MB by default,
  /// which at this preset is roughly a minute of footage.
  ///
  /// A minute of 4K would be tens of megabytes that never leave a phone on
  /// a weak connection — and an unuploaded recording is worth nothing, since
  /// the point of uploading is to survive the phone being taken. Medium is
  /// legible enough to identify a face or a weapon and small enough to
  /// actually arrive.
  ///
  /// If a recording does exceed the cap, the audio is already uploaded
  /// first and the video failure is caught, so the outcome is a missing
  /// video rather than a lost emergency recording.
  static const _resolution = ResolutionPreset.medium;

  static const _mimeType = 'video/mp4';

  Future<List<CameraDescription>> _cameras() async {
    if (_injectedCameras != null) return _injectedCameras;
    try {
      return await availableCameras();
    } on CameraException {
      return const [];
    }
  }

  @override
  Future<bool> isSupported() async {
    if (kIsWeb) return false;
    return (await _cameras()).isNotEmpty;
  }

  @override
  Future<bool> hasPermission() async {
    return Permission.camera.status.then((status) => status.isGranted);
  }

  @override
  Future<bool> requestPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  @override
  Future<void> start() async {
    if (_isRecording) return;

    final cameras = await _cameras();
    if (cameras.isEmpty) {
      throw const EvidenceRecorderException(EvidenceRecorderFailure.unsupported);
    }

    final status = await Permission.camera.status;
    if (status.isPermanentlyDenied) {
      throw const EvidenceRecorderException(
        EvidenceRecorderFailure.permissionPermanentlyDenied,
      );
    }
    if (!status.isGranted && !await requestPermission()) {
      throw const EvidenceRecorderException(EvidenceRecorderFailure.permissionDenied);
    }

    // Rear camera when there is one: it is the lens pointing away from the
    // wearer, which is where anything worth recording is. Falls back to
    // whatever exists rather than refusing.
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    // `enableAudio: false` deliberately. The audio recorder is already
    // holding the microphone; two capture sessions competing for it ends
    // with one of them failing, and the one that must not fail is audio.
    final controller = CameraController(
      camera,
      _resolution,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();
      await controller.startVideoRecording();
    } on CameraException catch (error) {
      await controller.dispose();
      throw EvidenceRecorderException(EvidenceRecorderFailure.failed, error.description);
    }

    _controller = controller;
    _isRecording = true;
  }

  @override
  Future<EvidenceRecording?> stop() async {
    final controller = _controller;
    if (controller == null || !_isRecording) return null;

    _isRecording = false;
    XFile? file;
    try {
      file = await controller.stopVideoRecording();
    } on CameraException {
      // A camera that died mid-recording costs the video, not the alert.
      await _disposeController();
      return null;
    }

    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return EvidenceRecording(bytes: bytes, mimeType: _mimeType);
    } finally {
      // Same rule as audio: the local copy goes as soon as it is read. A
      // recording of an assault left in the device's temp directory is one
      // file-manager app away from the person it was recorded about.
      await _deleteQuietly(file.path);
      await _disposeController();
    }
  }

  @override
  Future<void> cancel() async {
    final controller = _controller;
    if (controller == null) {
      _isRecording = false;
      return;
    }
    _isRecording = false;
    try {
      final file = await controller.stopVideoRecording();
      await _deleteQuietly(file.path);
    } on CameraException {
      // Nothing to discard.
    } finally {
      await _disposeController();
    }
  }

  @override
  Future<void> dispose() async {
    if (_isRecording) {
      await cancel();
      return;
    }
    await _disposeController();
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      await controller.dispose();
    } on CameraException {
      // Already gone.
    }
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Best effort — a file we cannot delete is not worth failing an
      // emergency over, and the bytes are already on their way to the
      // server.
    }
  }
}
