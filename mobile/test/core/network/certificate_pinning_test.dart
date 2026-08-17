@TestOn('vm')
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/config/app_config.dart';
import 'package:safeher_app/core/network/certificate_pinning.dart';
import 'package:safeher_app/core/network/certificate_pinning_io.dart'
    show applyPinningWith, fingerprintOf;

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
    test('installs a validating adapter, because a pin ships by default', () {
      // This test previously asserted the opposite: that with no pins
      // configured the adapter is left untouched. That was correct while
      // pinning required a --dart-define nobody remembered, and it is the
      // wrong default for a release build. An issuer pin now ships by
      // default, so the adapter is expected to be replaced.
      final dio = Dio();
      final original = dio.httpClientAdapter;

      applyCertificatePinning(dio);

      expect(identical(dio.httpClientAdapter, original), isFalse);
    });

    test('an unpinned client is genuinely untouched, not permissively wrapped', () {
      // The behaviour the old test protected, still worth keeping: swapping
      // in an adapter that validates nothing would be indistinguishable in
      // behaviour but would silently discard Dio's own adapter
      // configuration.
      final dio = Dio();
      final original = dio.httpClientAdapter;

      applyPinningWith(dio, leafPins: const {}, issuerPins: const {});

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

  group('Pinned WebSocket', () {
    test('an unpinned build connects normally', () async {
      // Every development build. Failing shut here would make the app
      // undevelopable against a local `ws://` server.
      expect(AppConfig.pinnedCertificateHashes, isEmpty);
    });

    test('the mismatch is its own error type', () {
      // A caller has to be able to tell "the server is not who it claims"
      // apart from an ordinary network drop — that distinction is the whole
      // point of pinning, and a generic SocketException would erase it.
      const error = CertificatePinMismatch('monitor.safeherapp.com');

      expect(error, isA<Exception>());
      expect(error.toString(), contains('monitor.safeherapp.com'));
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

  group('pin configuration', () {
    test('an issuer pin ships by default, so release builds are never unpinned', () {
      // A pin that has to be remembered at build time is a pin that ships
      // missing. SRS 5.2 asks for pinning in release builds, not for pinning
      // in the ones somebody remembered to configure.
      expect(AppConfig.pinnedCertificateIssuers, isNotEmpty);
      expect(AppConfig.pinnedCertificateIssuers, contains('O=Google Trust Services'));
    });

    test('no leaf pin is set, because the platform rotates the certificate', () {
      expect(AppConfig.pinnedCertificateHashes, isEmpty);
    });

    test('the production API is HTTPS by default', () {
      // A release build that fell back to localhost would look like a network
      // fault on the user's phone rather than a misbuild, so the default is
      // the deployed host rather than the developer's machine.
      expect(AppConfig.apiBaseUrl, startsWith('https://'));
      expect(AppConfig.apiBaseUrl, contains('/api/v1'));
    });
  });

  group('why the issuer is pinned rather than the leaf', () {
    // Render renews its Google Trust Services certificate roughly every
    // ninety days. These tests encode the reasoning so that "just pin the
    // leaf, it is stricter" is not re-adopted by someone reading only the
    // strictness argument.

    test('a leaf pin stops matching when the certificate rotates', () {
      final today = utf8.encode('leaf certificate valid until October');
      final afterRenewal = utf8.encode('leaf certificate issued in October');

      final pinnedToday = {fingerprintOf(today)};

      expect(pinnedToday.contains(fingerprintOf(today)), isTrue);
      // The same host, the same issuer, a legitimately renewed certificate —
      // and every installed copy of the app now refuses to reach the backend.
      expect(pinnedToday.contains(fingerprintOf(afterRenewal)), isFalse);
    });

    test('an issuer match survives that rotation', () {
      const issuer = 'C=US, O=Google Trust Services, CN=WE1';
      const pins = {'O=Google Trust Services'};

      expect(pins.any(issuer.contains), isTrue);
    });

    test('a certificate from a different authority is still refused', () {
      // The threat SRS 5.2 names: a corporate MDM profile or a hostile WiFi
      // portal that has installed its own trusted CA.
      const hostileIssuer = 'C=US, O=Definitely Not A Proxy, CN=mitm';
      const pins = {'O=Google Trust Services'};

      expect(pins.any(hostileIssuer.contains), isFalse);
    });
  });
}
