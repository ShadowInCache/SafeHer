import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Writes the PDF to a temporary file and opens the system share sheet.
///
/// A temporary file, not a permanent one: the copy that matters is wherever
/// the user sends it. Leaving forensic reports accumulating in app storage
/// would be another place for them to leak from.
Future<bool> sharePdf({required Uint8List bytes, required String filename}) async {
  if (bytes.isEmpty) return false;
  try {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: 'SafeHer incident report',
    );
    return true;
  } catch (_) {
    return false;
  }
}
