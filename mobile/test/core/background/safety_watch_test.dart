import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/background/safety_foreground_service.dart';
import 'package:safeher_app/core/background/safety_watch.dart';

import '../../test_utils/fake_foreground_service.dart';

/// The foreground service used to be started by one consumer — a connected
/// glove — and by nothing else. A Safe Journey armed with no glove paired
/// therefore ran with no service at all, so Android froze the process when the
/// screen went off and the speech recogniser, the camera policy timer and the
/// once-a-second post of the fused score all stopped. `threatPipelineArmed`
/// watches only the journey, so the app went on saying it was armed.
///
/// These tests pin the property that makes that impossible: the service's
/// lifetime is the union of the reasons that need it, and no reason's ending
/// can switch off another's.
void main() {
  late FakeForegroundService service;
  late ProviderContainer container;

  ProviderContainer build() {
    final created = ProviderContainer(overrides: [
      safetyForegroundServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(created.dispose);
    return created;
  }

  setUp(() {
    service = FakeForegroundService();
    container = build();
  });

  SafetyWatch watch() => container.read(safetyWatchProvider.notifier);

  group('a journey alone keeps the process alive', () {
    test('claiming the journey starts the service', () async {
      await watch().claim(WatchReason.journey);

      expect(service.startCalls, 1);
      expect(service.running, isTrue);
      expect(container.read(safetyWatchProvider), isTrue,
          reason: 'this is the bug: a journey with no glove had no service');
    });

    test('the journey declares the microphone reason', () async {
      // The reason set is what decides the Android service type, and a journey
      // whose `microphone` type is never declared is a journey whose audio
      // Android 14+ stops delivering the moment the screen goes off.
      await watch().claim(WatchReason.journey);

      expect(service.lastReasons, contains(WatchReason.journey));
    });

    test('nothing is started before anything claims', () {
      container.read(safetyWatchProvider);

      expect(service.startCalls, 0,
          reason: 'a "watching" notification over nothing is the same lie, '
              'pointed the other way');
      expect(container.read(safetyWatchProvider), isFalse);
    });
  });

  group('neither reason can switch the other off', () {
    test('a journey ending leaves a connected glove watched', () async {
      await watch().claim(WatchReason.glove);
      await watch().claim(WatchReason.journey);

      await watch().release(WatchReason.journey);

      expect(service.stopCalls, 0,
          reason: 'stopping here would take the glove BLE stream down with it');
      expect(service.running, isTrue);
      expect(service.lastReasons, {WatchReason.glove},
          reason: 'the microphone type must be given up with the journey');
      expect(container.read(safetyWatchProvider), isTrue);
    });

    test('a glove dropping leaves an armed journey listening', () async {
      await watch().claim(WatchReason.journey);
      await watch().claim(WatchReason.glove);

      await watch().release(WatchReason.glove);

      expect(service.stopCalls, 0);
      expect(service.running, isTrue);
      expect(service.lastReasons, {WatchReason.journey});
    });

    test('the service stops only once the last reason is gone', () async {
      await watch().claim(WatchReason.glove);
      await watch().claim(WatchReason.journey);

      await watch().release(WatchReason.glove);
      expect(service.stopCalls, 0);

      await watch().release(WatchReason.journey);

      expect(service.stopCalls, 1);
      expect(service.running, isFalse);
      expect(container.read(safetyWatchProvider), isFalse);
    });

    test('a second reason re-declares rather than being ignored', () async {
      // A journey starting under an already-running glove watch has to add the
      // microphone type. Short-circuiting on "already running" would leave the
      // service declared for a BLE link only, and the audio would die on lock
      // with everything on screen still claiming to work.
      await watch().claim(WatchReason.glove);
      await watch().claim(WatchReason.journey);

      expect(service.startCalls, 2);
      expect(service.startedWith.last, {WatchReason.glove, WatchReason.journey});
    });
  });

  group('claims are idempotent', () {
    test('claiming twice starts once', () async {
      await watch().claim(WatchReason.journey);
      await watch().claim(WatchReason.journey);

      expect(service.startCalls, 1,
          reason: 'a re-entrant listener must not turn into two starts');
    });

    test('releasing something never claimed does nothing', () async {
      await watch().claim(WatchReason.journey);

      await watch().release(WatchReason.glove);

      expect(service.stopCalls, 0,
          reason: 'an undercounting release would strand the journey');
      expect(service.running, isTrue);
    });

    test('releasing twice stops once', () async {
      await watch().claim(WatchReason.journey);

      await watch().release(WatchReason.journey);
      await watch().release(WatchReason.journey);

      expect(service.stopCalls, 1);
    });
  });

  group('a refused service is reported, not assumed', () {
    test('reports false when the platform will not start it', () async {
      // Notification permission denied, or an OEM that kills background work.
      service.startSucceeds = false;

      await watch().claim(WatchReason.journey);

      expect(service.startCalls, 1);
      expect(container.read(safetyWatchProvider), isFalse,
          reason: 'asking for the service is not the same as having it');
    });

    test('the reason is still tracked, so a later claim re-declares', () async {
      service.startSucceeds = false;
      await watch().claim(WatchReason.journey);

      service.startSucceeds = true;
      await watch().claim(WatchReason.glove);

      expect(service.startedWith.last, {WatchReason.glove, WatchReason.journey},
          reason: 'a failed start must not lose the reason it was asked for');
      expect(container.read(safetyWatchProvider), isTrue);
    });
  });

  test('the published reasons cannot be mutated from outside', () async {
    await watch().claim(WatchReason.journey);

    expect(
      () => watch().reasons.add(WatchReason.glove),
      throwsUnsupportedError,
      reason: 'the service types are derived from this set',
    );
  });
}
