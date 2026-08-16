library;

/// Resolves [EvidenceRecorder] to the implementation this platform can run.
///
/// `evidence_recorder_io.dart` imports `dart:io` to read the finished
/// recording off disk, which throws on web — so it is reachable only
/// through this conditional export, never by a direct import.
export 'evidence_recorder_stub.dart'
    if (dart.library.io) 'evidence_recorder_io.dart';
