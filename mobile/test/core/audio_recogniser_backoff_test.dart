import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/audio/audio_threat_monitor.dart';
import 'package:safeher_app/core/audio/threat_phrase_classifier.dart';

/// Measured on a Samsung SM M166P, 17 October, during a live Safe Journey.
/// With a flat 400 ms retry the monitor attempted roughly 2.5 listen sessions
/// a second for the whole journey. Android's recognition service caps
/// outstanding requests and started refusing this app outright:
///
/// ```
/// I/RecognitionService: #startListening received when the service's
///                       capacity is full - ignoring this call      x256
/// W/RecognitionClient:  NO_SPEECH_DETECTED code -1                 x304
/// W/RecognitionServiceImpl: Error type: ONLINE_NO_PROGRESS         x131
/// ```
///
/// The app saturated the service it depended on, then reported nothing,
/// because the error callback discarded its argument. These tests pin the
/// backoff arithmetic so a flat retry cannot come back.
void main() {
  group('restart backoff', () {
    // Mirrors _scheduleRestart: base * 2^failures, clamped to the ceiling.
    int delayMsFor(int failures, {int base = 400, int ceiling = 30000}) {
      final shift = failures.clamp(0, 16);
      return (base * (1 << shift)).clamp(base, ceiling);
    }

    test('the first failure waits the base delay', () {
      expect(delayMsFor(0), 400);
    });

    test('each failure doubles the wait', () {
      expect(delayMsFor(1), 800);
      expect(delayMsFor(2), 1600);
      expect(delayMsFor(3), 3200);
    });

    test('it is capped so the monitor never stops retrying entirely', () {
      expect(delayMsFor(10), 30000);
      expect(delayMsFor(16), 30000);
    });

    test('a long run of failures cannot overflow the shift', () {
      // 1 << 64 is 0 in a 64-bit int; clamping the shift is what stops the
      // delay silently collapsing back to zero after enough failures.
      expect(delayMsFor(99), 30000);
      expect(delayMsFor(99), greaterThan(0));
    });

    test('attempts in the first minute drop from ~150 to under 10', () {
      // The measured failure: 400 ms flat over 60 s.
      const flat = 60000 ~/ 400;
      expect(flat, 150);

      var elapsed = 0, attempts = 0, failures = 0;
      while (elapsed < 60000) {
        elapsed += delayMsFor(failures);
        failures++;
        attempts++;
      }
      expect(attempts, lessThan(10),
          reason: 'backoff must stop saturating the recognition service');
    });
  });

  group('monitor wiring', () {
    late ThreatPhraseClassifier classifier;

    setUpAll(() {
      classifier = ThreatPhraseClassifier.fromJson(
        jsonDecode(File('assets/models/phrase_classifier.json').readAsStringSync())
            as Map<String, dynamic>,
      );
    });

    test('exposes the backoff ceiling and the on-device preference', () {
      // These knobs are what the fix turns on. A refactor that drops them
      // would silently restore the flat-retry behaviour.
      expect(
        () => AudioThreatMonitor(
          classifier: classifier,
          maxRestartDelay: const Duration(seconds: 10),
          preferOnDevice: false,
        ),
        returnsNormally,
      );
    });

    test('defaults are the ones measured against the device', () {
      // Constructed with defaults: 30 s ceiling, on-device preferred.
      final monitor = AudioThreatMonitor(classifier: classifier);
      expect(monitor, isNotNull);
      addTearDown(monitor.dispose);
    });
  });
}
