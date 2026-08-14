import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/voice/voice_command.dart';

void main() {
  const matcher = VoiceCommandMatcher();

  group('VoiceCommandMatcher', () {
    test('matches the SOS phrases', () {
      expect(matcher.match('help me'), VoiceCommand.startSos);
      expect(matcher.match('Start SOS'), VoiceCommand.startSos);
      expect(matcher.match('please send sos now'), VoiceCommand.startSos);
    });

    test('matches cancellation phrases', () {
      expect(matcher.match('cancel SOS'), VoiceCommand.cancelSos);
      expect(matcher.match('false alarm'), VoiceCommand.cancelSos);
    });

    test('prefers cancellation when a phrase could read as both', () {
      // The safer reading of an ambiguous utterance is standing an alert
      // down — and cancelling still has to pass the PIN gate.
      expect(matcher.match('cancel sos help me'), VoiceCommand.cancelSos);
    });

    test('matches the remaining commands', () {
      expect(matcher.match('call my emergency contact'), VoiceCommand.callPrimaryContact);
      expect(matcher.match('share my location'), VoiceCommand.shareLocation);
      expect(matcher.match('start safe journey'), VoiceCommand.startJourney);
      expect(matcher.match('find help nearby'), VoiceCommand.showNearbyHelp);
    });

    test('is case- and punctuation-insensitive', () {
      expect(matcher.match('HELP ME!'), VoiceCommand.startSos);
      expect(matcher.match('Cancel, SOS.'), VoiceCommand.cancelSos);
    });

    test('ignores bare "help", which appears in ordinary speech', () {
      expect(matcher.match('help'), isNull);
      expect(matcher.match('can you help with dinner'), isNull);
    });

    test('returns null for unrelated speech and empty input', () {
      expect(matcher.match('what is the weather tomorrow'), isNull);
      expect(matcher.match(''), isNull);
      expect(matcher.match('    '), isNull);
    });

    test('every command advertises at least one phrase', () {
      for (final command in VoiceCommand.values) {
        expect(matcher.phrasesFor(command), isNotEmpty, reason: '$command has no phrases');
        // Each advertised phrase must actually resolve back to its command.
        for (final phrase in matcher.phrasesFor(command)) {
          expect(matcher.match(phrase), command, reason: '"$phrase" did not match $command');
        }
      }
    });
  });
}
