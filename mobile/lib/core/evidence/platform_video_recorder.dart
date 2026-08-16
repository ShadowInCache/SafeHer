library;

/// Resolves [VideoEvidenceRecorder] to the implementation this platform can
/// run.
///
/// `video_recorder_io.dart` imports `dart:io` to read the finished recording
/// off disk, which throws on web — so it is reachable only through this
/// conditional export, never by a direct import.
export 'video_recorder_stub.dart'
    if (dart.library.io) 'video_recorder_io.dart';
