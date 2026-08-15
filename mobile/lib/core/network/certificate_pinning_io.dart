import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../config/app_config.dart';

/// Native (Android/iOS/desktop) certificate pinning.
///
/// Dio calls [IOHttpClientAdapter.validateCertificate] for the leaf
/// certificate of every connection, *after* the platform has already
/// accepted the chain. That ordering is what makes this a pin rather than a
/// replacement for CA validation: a certificate has to be both properly
/// issued and one of ours.
void applyCertificatePinning(Dio dio) {
  final pins = AppConfig.pinnedCertificateHashes;
  if (pins.isEmpty) return;

  dio.httpClientAdapter = IOHttpClientAdapter(
    validateCertificate: (certificate, host, port) {
      if (certificate == null) return false;
      return pins.contains(fingerprintOf(certificate.der));
    },
  );
}

/// Base64-encoded SHA-256 of a DER-encoded certificate — the same value
/// `openssl x509 -outform DER | openssl dgst -sha256 -binary | openssl base64`
/// prints, so a pin can be read off a live host and pasted into the build
/// command without conversion.
///
/// Exposed for tests: pinning that cannot be exercised without a live TLS
/// handshake is pinning nobody checks.
String fingerprintOf(List<int> der) => base64.encode(sha256.convert(der).bytes);
