import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/audio/audio_threat_monitor.dart';
import 'package:safeher_app/core/audio/recognizer_tone.dart';
import 'package:safeher_app/core/audio/threat_phrase_classifier.dart';

/// Records what the monitor asked the native side to do.
class _FakeTone implements RecognizerTone {
  final calls = <String>[];

  @override
  Future<bool> mute() async {
    calls.add('mute');
    return true;
  }

  @override
  Future<void> unmute() async => calls.add('unmute');
}

/// Android plays a beep whenever speech recognition starts or stops. The
/// monitor restarts recognition every few seconds, so a quiet walk produced a
/// beep roughly every four seconds for the whole journey. These cover the
/// mute that suppresses it — and, more importantly, the paths that must put
/// the phone's audio back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RecognizerTone channel', () {
    const channel = MethodChannel('io.github.akshayag.safeher/recognizer_tone');
    final calls = <MethodCall>[];

    void mockWith(Future<Object?>? Function(MethodCall) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return handler(call);
      });
    }

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      calls.clear();
    });

    test('a missing native side is survivable, not fatal', () async {
      // No handler registered -> MissingPluginException. An older build of the
      // native side must not stop the monitor from listening.
      const tone = RecognizerTone(channel: channel);
      expect(await tone.mute(), isFalse);
      await tone.unmute(); // must not throw
    });

    test('a platform refusal reports false rather than throwing', () async {
      // Do Not Disturb can forbid volume changes. The beep stays; listening
      // continues. That is the right way round.
      mockWith((_) async => throw PlatformException(code: 'dnd'));
      const tone = RecognizerTone(channel: channel);
      expect(await tone.mute(), isFalse);
      await tone.unmute();
    });

    test('reports whether the streams were actually muted', () async {
      mockWith((call) async => call.method == 'mute' ? true : null);
      const tone = RecognizerTone(channel: channel);
      expect(await tone.mute(), isTrue);
      expect(calls.single.method, 'mute');
    });

    test('unmute asks the native side to restore', () async {
      mockWith((_) async => null);
      const tone = RecognizerTone(channel: channel);
      await tone.unmute();
      expect(calls.single.method, 'unmute');
    });
  });

  group('AudioThreatMonitor tone handling', () {
    late ThreatPhraseClassifier classifier;

    setUpAll(() {
      classifier = ThreatPhraseClassifier.fromJson(
        jsonDecode(File('assets/models/phrase_classifier.json').readAsStringSync())
            as Map<String, dynamic>,
      );
    });

    test('a recogniser that will not start leaves the audio alone', () async {
      // There is no speech plugin on the test engine, so `initialize` fails
      // exactly as it would on a phone that refuses the microphone.
      final tone = _FakeTone();
      final monitor = AudioThreatMonitor(classifier: classifier, tone: tone);

      expect(await monitor.start(), isFalse);
      // Silencing her music for a monitor that is not listening would be a
      // cost with nothing bought for it.
      expect(tone.calls, isNot(contains('mute')));

      await monitor.dispose();
    });

    test('stopping restores the audio even when nothing was muted', () async {
      final tone = _FakeTone();
      final monitor = AudioThreatMonitor(classifier: classifier, tone: tone);

      await monitor.stop();

      // `stop` is what runs when a journey ends and when the app closes. If it
      // ever skipped the unmute, the phone would stay silent afterwards and
      // the user would have to hunt through volume settings to fix it.
      expect(tone.calls, contains('unmute'));

      await monitor.dispose();
    });

    test('disposing restores the audio', () async {
      final tone = _FakeTone();
      final monitor = AudioThreatMonitor(classifier: classifier, tone: tone);

      await monitor.dispose();

      expect(tone.calls, contains('unmute'));
    });
  });
}
