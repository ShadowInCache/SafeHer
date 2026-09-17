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

  group('the glove keeps watching in the background', () {
    const watching = DetectionSources(
      backend: _backendOff,
      gloveListening: true,
      backgroundWatchActive: true,
    );

    test('stops claiming the foreground limit once it no longer applies', () {
      // The foreground service closes this gap. Leaving the old sentence up
      // would under-report in the direction that makes someone keep a phone
      // in her hand when she does not have to.
      expect(watching.detail.toLowerCase(), isNot(contains('only does this while')));
      expect(watching.detail.toLowerCase(), contains('pocket'));
      expect(watching.headline, 'Your glove is watching');
    });

    test('ties the promise to the notification that proves it', () {
      // The service is the reason this is true, and the notification is how
      // she can see it is still running. Naming it makes the claim checkable
      // rather than something she has to take on faith.
      expect(watching.detail.toLowerCase(), contains('notification'));
    });

    test('still points at the manual paths', () {
      expect(watching.detail, contains('SOS'));
      expect(watching.detail.toLowerCase(), contains('shake'));
    });

    test('defaults to off, so the claim needs the platform to confirm it', () {
      // Asking for the service is not the same as having it: notification
      // permission can be denied and OEMs kill background work. The
      // pessimistic default is the safe one.
      const notConfirmed = DetectionSources(backend: _backendOff, gloveListening: true);

      expect(notConfirmed.backgroundWatchActive, isFalse);
      expect(notConfirmed.detail.toLowerCase(), contains('only does this while'));
    });

    test('a background watch cannot invent detection with no glove', () {
      // If the flag ever survived a disconnect, this would claim protection
      // from a service that has nothing to listen to.
      const noGlove = DetectionSources(
        backend: _backendOff,
        gloveListening: false,
        backgroundWatchActive: true,
      );

      expect(noGlove.anyActive, isFalse);
      expect(noGlove.headline, 'Automatic detection is not active yet');
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

  group('journey detection', () {
    test('a running journey is reported even with no hardware paired', () {
      // The pipeline listens through the phone's own microphone, so it can be
      // the only active detector while nothing at all is connected. Before
      // this was wired in, this screen said "SafeHer cannot detect a threat by
      // itself" while the phrase classifier was actively scoring speech.
      const sources = DetectionSources(
        backend: DetectionStatus.unknown,
        gloveListening: false,
        journeyDetectionActive: true,
      );

      expect(sources.anyActive, isTrue);
      expect(sources.headline, 'Detection is on for this journey');
    });

    test('says what is listened to and what happens to it', () {
      const sources = DetectionSources(
        backend: DetectionStatus.unknown,
        gloveListening: false,
        journeyDetectionActive: true,
      );

      // Consent depends on the detail, not the headline: that speech is
      // recognised on the device, that it is discarded, and that it stops.
      expect(sources.detail, contains('discarded'));
      expect(sources.detail, contains('only a score leaves the device'));
      expect(sources.detail, contains('stops when the journey ends'));
    });

    test('a connected glove still takes precedence in the headline', () {
      // Both can be true at once. The glove is named because it is the one
      // with the caveat about running off screen.
      const sources = DetectionSources(
        backend: DetectionStatus.unknown,
        gloveListening: true,
        journeyDetectionActive: true,
      );

      expect(sources.headline, 'Your glove is watching');
    });

    test('names the off-screen limit while the service is not confirmed', () {
      // The mirror of the glove's caveat, and the defect this pairs with: the
      // journey pipeline had no foreground service of its own, so a journey
      // armed with no glove paired stopped listening on screen-off while this
      // text promised listening and `armed` stayed true.
      const sources = DetectionSources(
        backend: DetectionStatus.unknown,
        gloveListening: false,
        journeyDetectionActive: true,
      );

      expect(sources.detail.toLowerCase(), contains('only does this while'));
      expect(sources.detail.toLowerCase(), contains('screen off'));
      // The consent facts survive the caveat; they are not alternatives to it.
      expect(sources.detail, contains('discarded'));
      expect(sources.detail, contains('only a score leaves the device'));
      expect(sources.detail, contains('stops when the journey ends'));
    });

    test('drops the limit and names the notification once the service runs',
        () {
      const sources = DetectionSources(
        backend: DetectionStatus.unknown,
        gloveListening: false,
        journeyDetectionActive: true,
        backgroundWatchActive: true,
      );

      expect(
        sources.detail.toLowerCase(),
        isNot(contains('only does this while')),
        reason: 'leaving it up would keep a phone in her hand needlessly',
      );
      // The notification is how she can check the claim rather than trust it.
      expect(sources.detail.toLowerCase(), contains('notification'));
      expect(sources.detail.toLowerCase(), contains('screen off'));
      expect(sources.detail, contains('discarded'));
      expect(sources.detail, contains('only a score leaves the device'));
      expect(sources.detail, contains('stops when the journey ends'));
    });

    test('a background watch cannot invent journey detection', () {
      // The same guard the glove branch has: the flag must never be the thing
      // that makes the screen claim protection.
      const sources = DetectionSources(
        backend: DetectionStatus.unknown,
        gloveListening: false,
        journeyDetectionActive: false,
        backgroundWatchActive: true,
      );

      expect(sources.anyActive, isFalse);
      expect(sources.headline, 'Automatic detection is not active yet');
    });

    test('no journey and no glove stays pessimistic', () {
      const sources = DetectionSources(
        backend: DetectionStatus.unknown,
        gloveListening: false,
        journeyDetectionActive: false,
      );

      expect(sources.anyActive, isFalse);
      expect(sources.headline, 'Automatic detection is not active yet');
    });
  });
}
