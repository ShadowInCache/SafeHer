import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
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
void applyCertificatePinning(Dio dio) => applyPinningWith(
      dio,
      leafPins: AppConfig.pinnedCertificateHashes,
      issuerPins: AppConfig.pinnedCertificateIssuers,
    );

/// The pinning decision, with its inputs passed in.
///
/// [AppConfig] reads its pins from compile-time constants, so a test cannot
/// vary them. Without this seam the only testable case is whichever set
/// happens to be baked into the test binary — and the case worth testing is
/// the one that is *not* the default.
@visibleForTesting
void applyPinningWith(
  Dio dio, {
  required Set<String> leafPins,
  required Set<String> issuerPins,
}) {
  if (leafPins.isEmpty && issuerPins.isEmpty) return;

  dio.httpClientAdapter = IOHttpClientAdapter(
    validateCertificate: (certificate, host, port) {
      if (certificate == null) return false;

      // Leaf pins win when configured: they are the strictest statement
      // available, and someone who set one meant it.
      if (leafPins.isNotEmpty) {
        return leafPins.contains(fingerprintOf(certificate.der));
      }

      // Otherwise the issuer must be one we recognise. Deliberately a
      // `contains` against the configured value rather than equality: the
      // exact formatting of an issuer DN varies between platforms, and a
      // pin that fails on iOS but passes on Android would be discovered by
      // users rather than by us.
      final issuer = certificate.issuer;
      return issuerPins.any(issuer.contains);
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
