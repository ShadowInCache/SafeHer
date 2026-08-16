import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';
import 'certificate_pinning.dart';
import 'certificate_pinning_io.dart' show fingerprintOf;

/// Native WebSocket connect, pinned to the same certificates as the HTTP API.
///
/// `WebSocketChannel.connect` offers no hook to inspect the server's
/// certificate, so the socket is built from a `dart:io` [HttpClient] we can
/// configure — the one place the platform hands the leaf certificate to
/// application code.
///
/// **How the pin is enforced, and what it costs.** `badCertificateCallback`
/// only fires when validation has already failed, so a client trusting the
/// system roots never sees the certificate of a *successful* handshake. To
/// get the certificate at all, the client is built with no trusted roots:
/// every chain then fails, every certificate reaches the callback, and the
/// pin becomes the sole trust anchor.
///
/// That deliberately discards the CA's own checks, so the two that matter
/// are re-applied here by hand: the certificate must be inside its validity
/// window, and it must match a configured pin. Hostname verification is not
/// re-implemented because pinning a specific certificate binds identity more
/// tightly than a name match would.
///
/// With no pins configured — every development build — the client keeps
/// ordinary CA validation. Failing shut there would make the app
/// undevelopable against a local server, exactly as in
/// `certificate_pinning.dart`.
Future<WebSocketChannel> connectPinnedWebSocket(Uri uri) async {
  final pins = AppConfig.pinnedCertificateHashes;
  if (pins.isEmpty || uri.scheme != 'wss') {
    return WebSocketChannel.connect(uri);
  }

  final client = HttpClient(context: SecurityContext(withTrustedRoots: false))
    ..badCertificateCallback = (X509Certificate certificate, String host, int port) {
      if (!pins.contains(fingerprintOf(certificate.der))) return false;
      final now = DateTime.now().toUtc();
      if (now.isBefore(certificate.startValidity.toUtc())) return false;
      if (now.isAfter(certificate.endValidity.toUtc())) return false;
      return true;
    };

  try {
    final socket = await WebSocket.connect(uri.toString(), customClient: client);
    return IOWebSocketChannel(socket);
  } on HandshakeException {
    client.close(force: true);
    // Surfaced as its own type so a caller can tell "the server is not who
    // it claims" apart from an ordinary network drop, which is the whole
    // point of pinning.
    throw CertificatePinMismatch(uri.host);
  } catch (_) {
    client.close(force: true);
    rethrow;
  }
}
