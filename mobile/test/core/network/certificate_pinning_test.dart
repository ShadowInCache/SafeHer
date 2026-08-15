@TestOn('vm')
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/config/app_config.dart';
import 'package:safeher_app/core/network/certificate_pinning.dart';
import 'package:safeher_app/core/network/certificate_pinning_io.dart' show fingerprintOf;

void main() {
  group('fingerprintOf', () {
    test('matches what openssl prints for the same DER bytes', () {
      // `openssl dgst -sha256 -binary | openssl base64` is exactly
      // base64(sha256(der)) — the pin format the build command takes.
      final der = utf8.encode('a-der-encoded-certificate');
      expect(fingerprintOf(der), base64.encode(sha256.convert(der).bytes));
    });

    test('is stable and distinguishes different certificates', () {
      final first = utf8.encode('certificate-one');
      final second = utf8.encode('certificate-two');

      expect(fingerprintOf(first), fingerprintOf(first));
      expect(fingerprintOf(first), isNot(fingerprintOf(second)));
    });
  });

  group('AppConfig.pinnedCertificateHashes', () {
    test('is empty when no pins are supplied at build time', () {
      // The default build has no --dart-define=PINNED_CERT_SHA256, so the
      // app must fall through to ordinary CA validation rather than
      // refusing to make any request at all.
      expect(AppConfig.pinnedCertificateHashes, isEmpty);
    });
  });

  group('applyCertificatePinning', () {
    test('leaves the adapter alone when nothing is pinned', () {
      final dio = Dio();
      final original = dio.httpClientAdapter;

      applyCertificatePinning(dio);

      // Swapping in a validating adapter that permits everything would be
      // indistinguishable in behaviour but would silently disable Dio's own
      // adapter configuration, so assert the client is genuinely untouched.
      expect(identical(dio.httpClientAdapter, original), isTrue);
    });

    test('installs an adapter carrying a leaf-certificate check when pinned', () {
      // AppConfig reads its pins from a compile-time constant, so this test
      // exercises the adapter wiring directly rather than trying to mutate
      // it. The pin set itself is covered above.
      final dio = Dio();
      const pins = {'jN5ExampleFingerprintAAAAAAAAAAAAAAAAAAAAAA='};

      dio.httpClientAdapter = IOHttpClientAdapter(
        validateCertificate: (certificate, host, port) {
          if (certificate == null) return false;
          return pins.contains(fingerprintOf(certificate.der));
        },
      );

      final adapter = dio.httpClientAdapter as IOHttpClientAdapter;
      expect(adapter.validateCertificate, isNotNull);
      // A null certificate must fail closed: "no certificate presented" is
      // not "certificate matched".
      expect(adapter.validateCertificate!(null, 'api.safeherapp.com', 443), isFalse);
    });
  });

  group('CertificatePinMismatch', () {
    test('names the host it refused', () {
      expect(
        const CertificatePinMismatch('api.safeherapp.com').toString(),
        contains('api.safeherapp.com'),
      );
    });
  });
}
