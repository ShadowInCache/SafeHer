import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/detection/detection_sources.dart';
import 'package:safeher_app/core/detection/detection_status.dart';

/// Detection is claimed to a woman deciding whether to rely on it. Both
/// directions of being wrong are dangerous: saying it is off when it is on
/// wastes a real protection, and saying it is on without its limits invites
/// someone to trust a pocketed phone that will not raise the alarm.
const _backendOff = DetectionStatus(
  pipelineLive: false,
  anyModelReady: false,
  scoresAreCallerSupplied: true,
);

const _backendOn = DetectionStatus(
  pipelineLive: true,
  anyModelReady: true,
  scoresAreCallerSupplied: false,
);

void main() {
  group('nothing is detecting', () {
    const sources = DetectionSources(backend: _backendOff, gloveListening: false);

    test('says so plainly', () {
      expect(sources.anyActive, isFalse);
      expect(sources.headline, 'Automatic detection is not active yet');
    });

    test('reassures that the manual paths still work', () {
      // The point of admitting this is that she reaches for SOS herself.
      expect(sources.detail, contains('SOS'));
      expect(sources.detail.toLowerCase(), contains('shake'));
    });
  });

  group('a connected glove counts as detection', () {
    const sources = DetectionSources(backend: _backendOff, gloveListening: true);

    test('is active even though the backend has no models', () {
      // The regression this file exists for: the glove runs its model on the
      // ESP32 with no server in the path, so the backend's opinion of its own
      // models cannot be the whole answer.
      expect(sources.anyActive, isTrue);
      expect(sources.gloveOnly, isTrue);
      expect(sources.headline, 'Your glove is watching');
    });

    test('states the foreground limit in the same breath', () {
      // Someone deciding whether to rely on this deserves the limit as much
      // as the capability. A phone in a pocket is the case the feature exists
      // for, and the case it does not cover.
      expect(sources.detail.toLowerCase(), contains('only does this while'));
      expect(sources.detail.toLowerCase(), contains('pocket'));
    });

    test('still points at the manual paths', () {
      expect(sources.detail, contains('SOS'));
    });
  });

  group('backend models serving', () {
    test('is active without a glove, and claims no glove limit', () {
      const sources = DetectionSources(backend: _backendOn, gloveListening: false);

      expect(sources.anyActive, isTrue);
      expect(sources.gloveOnly, isFalse);
      expect(sources.headline, 'Automatic detection is on');
      expect(
        sources.detail.toLowerCase(),
        isNot(contains('pocket')),
        reason: 'the foreground limit belongs to the glove, not to server-side detection',
      );
    });
  });

  group('both sources live', () {
    const sources = DetectionSources(backend: _backendOn, gloveListening: true);

    test('leads with the glove, since it is the one with a caveat', () {
      expect(sources.anyActive, isTrue);
      expect(sources.gloveOnly, isFalse, reason: 'the backend is detecting too');
      expect(sources.headline, 'Your glove is watching');
      expect(sources.detail.toLowerCase(), contains('pocket'));
    });
  });

  group('unknown backend', () {
    test('a live glove is still reported while the server is unreachable', () {
      // DetectionStatus.unknown is deliberately pessimistic about the server.
      // That pessimism must not erase a detector running on the user's wrist.
      const sources = DetectionSources(
        backend: DetectionStatus.unknown,
        gloveListening: true,
      );

      expect(sources.anyActive, isTrue);
      expect(sources.headline, 'Your glove is watching');
    });

    test('with no glove it stays pessimistic', () {
      const sources = DetectionSources(
        backend: DetectionStatus.unknown,
        gloveListening: false,
      );

      expect(sources.anyActive, isFalse,
          reason: 'claiming detection we cannot confirm is the dangerous error');
    });
  });
}
