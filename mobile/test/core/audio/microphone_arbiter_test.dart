import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/audio/microphone_arbiter.dart';

/// The platform hands the microphone to one caller at a time, and SafeHer has
/// two that want it. Everything here is about which one loses, and when.
void main() {
  late ProviderContainer container;
  MicrophoneArbiter notifier() =>
      container.read(microphoneArbiterProvider.notifier);
  MicrophoneUse current() => container.read(microphoneArbiterProvider);

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('starts idle', () {
    expect(current(), MicrophoneUse.idle);
  });

  group('evidence outranks listening', () {
    test('threat listening is refused while evidence holds the microphone', () {
      notifier().claimForEvidence();

      expect(notifier().claimForThreatListening(), isFalse);
      expect(
        current(),
        MicrophoneUse.evidence,
        reason: 'a refused claim must not displace the recording',
      );
    });

    test('evidence takes the microphone from threat listening', () {
      expect(notifier().claimForThreatListening(), isTrue);
      notifier().claimForEvidence();

      // The recording of an assault is what a court sees; a threat score
      // during the emergency has no decision left to inform.
      expect(current(), MicrophoneUse.evidence);
      expect(notifier().threatListeningAllowed, isFalse);
    });
  });

  group('handing it back', () {
    test('releasing evidence frees the device for listening again', () {
      notifier().claimForEvidence();
      notifier().releaseEvidence();

      expect(current(), MicrophoneUse.idle);
      expect(notifier().claimForThreatListening(), isTrue);
    });

    test('threat listening cannot release a claim it does not hold', () {
      // Otherwise leaving the emergency screen could hand the microphone to
      // nobody while the recorder still has it.
      notifier().claimForEvidence();
      notifier().releaseThreatListening();

      expect(current(), MicrophoneUse.evidence);
    });

    test('releasing evidence twice is harmless', () {
      notifier().claimForEvidence();
      notifier().releaseEvidence();
      notifier().releaseEvidence();

      expect(current(), MicrophoneUse.idle);
    });

    test('evidence release does not clobber a later listening claim', () {
      notifier().claimForEvidence();
      notifier().releaseEvidence();
      notifier().claimForThreatListening();
      notifier().releaseEvidence();

      expect(
        current(),
        MicrophoneUse.threatListening,
        reason: 'a stale release from the screen being disposed must not stop '
            'listening that has already resumed',
      );
    });
  });
}
