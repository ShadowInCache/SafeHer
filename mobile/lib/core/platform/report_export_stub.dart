import 'dart:typed_data';

/// Web build: no file system to stage the PDF in, and no share sheet to
/// hand it to. Reported rather than silently swallowed — the button used to
/// show "Preparing PDF export…" and then do nothing at all, which is the
/// failure mode this whole file exists to avoid.
Future<bool> sharePdf({required Uint8List bytes, required String filename}) async => false;
