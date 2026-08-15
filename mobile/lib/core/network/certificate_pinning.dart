import 'package:dio/dio.dart';

import 'certificate_pinning_stub.dart'
    if (dart.library.io) 'certificate_pinning_io.dart' as impl;

/// Certificate pinning for every outgoing API call — SRS §5.2 ("certificate
/// pinning in mobile app") and the SECURITY acceptance criteria.
///
/// Why this matters more here than in an ordinary app: SafeHer's traffic is
/// a woman's live GPS coordinates, her emergency contacts and her evidence
/// uploads. TLS alone trusts every CA in the device store, including one a
/// corporate MDM profile or a malicious "free WiFi" portal installed. A pin
/// means the app talks to *our* server or to nobody.
///
/// Pins are supplied at build time, never committed:
///
/// ```
/// flutter build apk --release \
///   --dart-define=API_BASE_URL=https://api.safeherapp.com/api/v1 \
///   --dart-define=PINNED_CERT_SHA256=<base64>,<backup-base64>
/// ```
///
/// Read the fingerprint of a live host with:
///
/// ```
/// openssl s_client -connect api.safeherapp.com:443 -servername api.safeherapp.com </dev/null \
///   | openssl x509 -outform DER | openssl dgst -sha256 -binary | openssl base64
/// ```
///
/// **Always configure at least two pins** — the certificate in use and the
/// next one. A single pin turns routine certificate renewal into a total
/// outage that only an app-store update can fix, and for this app an outage
/// means an SOS that does not send.
///
/// With no pins configured the app is left on ordinary CA validation rather
/// than failing shut: a development build against a local HTTP backend has
/// no certificate to pin, and refusing to run would make the app
/// undevelopable. Ship release builds with pins set.
void applyCertificatePinning(Dio dio) => impl.applyCertificatePinning(dio);

/// Thrown when a connection presents a certificate that matches no
/// configured pin. Surfaced as a `DioException` at the call site.
class CertificatePinMismatch implements Exception {
  const CertificatePinMismatch(this.host);

  final String host;

  @override
  String toString() =>
      'CertificatePinMismatch: the certificate presented by $host does not '
      'match any pinned fingerprint.';
}
