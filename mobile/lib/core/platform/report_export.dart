import 'dart:typed_data';

import 'report_export_stub.dart' if (dart.library.io) 'report_export_io.dart' as impl;

/// Hands an exported incident report to the system share sheet.
///
/// The share sheet rather than a silent download: a report's whole purpose
/// is to reach someone else — a police officer, a lawyer, a family member —
/// and the sheet is where the user already knows how to do that.
class ReportExport {
  const ReportExport();

  /// Returns false when the platform cannot share a file, so the caller can
  /// say why instead of appearing to do nothing.
  Future<bool> sharePdf({required Uint8List bytes, required String filename}) =>
      impl.sharePdf(bytes: bytes, filename: filename);
}
