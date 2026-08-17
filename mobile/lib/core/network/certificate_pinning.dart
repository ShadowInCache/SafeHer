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
/// **Two ways to pin, and the right one depends on who owns the
/// certificate.**
///
/// `PINNED_CERT_SHA256` pins the leaf. Strictest, and correct for a domain
/// whose certificate you renew yourself and can coordinate with a release.
///
/// `PINNED_CERT_ISSUERS` pins the issuing authority instead, and is what a
/// platform-managed certificate needs. Render serves a Google Trust Services
/// certificate for `onrender.com` and renews it roughly every ninety days; a
/// leaf pin would stop matching the day it rotated, taking the backend away
/// from every installed copy of SafeHer — including mid-emergency — with no
/// remedy but a store update. That is a worse outcome than the attack the
/// pin defends against, so the issuer is pinned instead. It still refuses a
/// certificate minted by any other authority, which is the hostile-WiFi or
/// corporate-MDM CA that SRS section 5.2 is about.
///
/// Read the current issuer with:
///
///   openssl s_client -connect HOST:443 -servername HOST < /dev/null \\
///     | openssl x509 -noout -issuer
///
/// **When pinning leaves, always configure at least two pins** — the certificate in use and the
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
