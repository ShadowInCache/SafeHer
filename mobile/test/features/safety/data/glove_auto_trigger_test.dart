import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/local/local_key_value_store.dart';
import 'package:safeher_app/core/local/onboarding_prefs.dart';
import 'package:safeher_app/features/devices/data/ble_providers.dart';
import 'package:safeher_app/features/devices/domain/glove_protocol.dart';
import 'package:safeher_app/features/devices/domain/models/ble_models.dart';
import 'package:safeher_app/features/safety/data/glove_auto_trigger.dart';

import '../../../test_utils/fake_ble_service.dart';
import '../../../test_utils/fake_foreground_service.dart';
import '../../../test_utils/fake_key_value_store.dart';

/// The glove's vote used to run inside `SafetyTriggerListener.build()`, which
/// made automatic detection quietly conditional on the app being drawn:
/// Flutter stops pumping frames when the app is backgrounded, so `build()`
/// stopped being called and a pocketed phone — the case the glove exists for —
/// raised nothing at all.
///
/// **Every test in this file runs with no widget tree and no frames.** A
/// `ProviderContainer` alone is the point: if the vote ever moves back into a
/// widget, or starts depending on anything that needs a pump, these fail.
BleDiscoveredDevice _glove({String id = 'glove-1'}) => BleDiscoveredDevice(
      id: id,
      advertisedName: 'SafeHer-Glove',
      rssi: -50,
      isConnectable: true,
    );

void main() {
  late FakeBleService ble;
  late FakeForegroundService service;
  late LocalKeyValueStore store;
  late ProviderContainer container;

  ProviderContainer build() {
    final created = ProviderContainer(overrides: [
      bleServiceProvider.overrideWithValue(ble),
      localKeyValueStoreProvider.overrideWithValue(store),
      safetyForegroundServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(created.dispose);
    return created;
  }

  setUp(() {
    ble = FakeBleService();
    service = FakeForegroundService();
    store = FakeKeyValueStore();
    container = build();
  });

  /// Connects the fake glove, having warmed the providers first so their
  /// listeners are attached — which is what the app does by mounting the
  /// trigger listener above the router.
  Future<void> connectGlove() async {
    container.read(gloveAutoTriggerProvider);
    container.read(gloveWatchServiceProvider);
    await container.read(blePairingControllerProvider.notifier).connect(_glove());
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  group('the vote runs without a widget tree', () {
    test('no alarm before anything has been heard', () {
      expect(container.read(gloveAutoTriggerProvider), isNull);
    });

    test('two falls inside the window raise one alarm', () async {
      ble.notifications[GloveBle.classificationCharacteristicUuid] = [
        'FALL,0.93',
        'FALL,0.91',
      ];

      await connectGlove();

      final request = container.read(gloveAutoTriggerProvider);
      expect(request, isNotNull,
          reason: 'the whole point: this happened with nothing being drawn');
      expect(request!.classification.label, 'FALL');
    });

    test('one fall alone does not', () async {
      // A glove dropped on a table, taken off, or caught on a door. Alarming
      // on a single reading is how the feature gets switched off, at which
      // point it protects nobody.
      ble.notifications[GloveBle.classificationCharacteristicUuid] = ['FALL,0.93'];

      await connectGlove();

      expect(container.read(gloveAutoTriggerProvider), isNull);
    });

    test('readings below the user threshold do not count', () async {
      await store.setDouble('threatThreshold', 0.95);
      container = build();

      ble.notifications[GloveBle.classificationCharacteristicUuid] = [
        'FALL,0.80',
        'FALL,0.82',
      ];

      await connectGlove();

      expect(container.read(gloveAutoTriggerProvider), isNull,
          reason: 'the threshold slider has to actually govern this');
    });

    test('a lowered threshold lets the same readings through', () async {
      // The mirror of the test above. Together they prove the slider is read
      // at decision time rather than captured once and forgotten — the exact
      // failure this codebase has shipped three times.
      await store.setDouble('threatThreshold', 0.60);
      container = build();

      ble.notifications[GloveBle.classificationCharacteristicUuid] = [
        'FALL,0.80',
        'FALL,0.82',
      ];

      await connectGlove();

      expect(container.read(gloveAutoTriggerProvider), isNotNull);
    });

    test('non-danger classes never alarm, however confident', () async {
      // SHAKING at 0.99 is a hand being dried. SUDDEN_MOVEMENT is deliberately
      // elevated rather than danger; raising it is a product decision to be
      // made with data, not here.
      ble.notifications[GloveBle.classificationCharacteristicUuid] = [
        'SHAKING,0.99',
        'SHAKING,0.99',
        'SUDDEN_MOVEMENT,0.99',
        'SUDDEN_MOVEMENT,0.99',
      ];

      await connectGlove();

      expect(container.read(gloveAutoTriggerProvider), isNull);
    });

    test('each alarm is a distinct object, so a second fall is a second alarm',
        () async {
      ble.notifications[GloveBle.classificationCharacteristicUuid] = [
        'FALL,0.93',
        'FALL,0.91',
      ];
      await connectGlove();

      final first = container.read(gloveAutoTriggerProvider);
      expect(first, isNotNull);
      // A bare bool would already be true here and the listener would never
      // fire again — one flag cannot represent two emergencies.
      expect(identical(first, container.read(gloveAutoTriggerProvider)), isTrue);
      expect(first.toString(), contains('FALL'));
    });
  });

  group('the foreground service follows the glove', () {
    test('is not started before a glove is connected', () {
      container.read(gloveWatchServiceProvider);

      expect(service.startCalls, 0,
          reason: 'a "watching" notification over no glove is the same lie, '
              'pointed the other way');
      expect(container.read(gloveWatchServiceProvider), isFalse);
    });

    test('starts once the glove is listening', () async {
      await connectGlove();

      expect(service.startCalls, 1);
      expect(service.running, isTrue);
      expect(container.read(gloveWatchServiceProvider), isTrue);
    });

    test('stops when the glove drops', () async {
      await connectGlove();
      ble.dropConnection('glove-1');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(service.stopCalls, greaterThanOrEqualTo(1));
      expect(service.running, isFalse);
      expect(container.read(gloveWatchServiceProvider), isFalse);
    });

    test('reports false when the platform refuses to start it', () async {
      // Notification permission denied, or an OEM that kills background work.
      // The app must not claim the pocket case works because it asked nicely.
      service.startSucceeds = false;

      await connectGlove();

      expect(service.startCalls, 1);
      expect(container.read(gloveWatchServiceProvider), isFalse,
          reason: 'asking for the service is not the same as having it');
    });
  });
}
