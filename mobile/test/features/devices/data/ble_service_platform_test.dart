import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/data/ble_service_flutter_blue_plus.dart';

/// Regression cover for a crash that took down the whole Device screen on
/// web with `Unsupported operation: Platform._operatingSystem`.
///
/// `canPromptToEnableBluetooth` is a plain getter, read during the pairing
/// sheet's `build`. It was implemented as `dart:io`'s `Platform.isAndroid`,
/// which throws on web — and a throw inside `build` is not something the
/// controller's error handling can catch, so the user got a red error page
/// instead of a message. `defaultTargetPlatform` answers the same question
/// on every target, web included.
///
/// These tests run on the VM, so they cannot reproduce the web throw
/// directly. What they can pin is the property that makes the bug
/// impossible: the getter is total, for every platform value, and never
/// reaches for `dart:io`.
void main() {
  group('FlutterBluePlusBleService platform checks', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('canPromptToEnableBluetooth answers for every platform without throwing', () {
      const service = FlutterBluePlusBleService();

      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        expect(
          () => service.canPromptToEnableBluetooth,
          returnsNormally,
          reason: '$platform must not throw — this getter runs inside build()',
        );
      }
    });

    test('only Android can be asked to power the radio on', () {
      const service = FlutterBluePlusBleService();

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(service.canPromptToEnableBluetooth, isTrue);

      // iOS gives apps no way to turn Bluetooth on; CoreBluetooth only lets
      // us point the user at Settings.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(service.canPromptToEnableBluetooth, isFalse);
    });
  });

  test('no library under lib/ imports dart:io', () {
    // The rule the crash taught us, enforced rather than remembered. SafeHer
    // ships to web as well as phones, and dart:io compiles there but throws
    // at runtime — so an accidental import is invisible to `flutter analyze`
    // and to every VM test, and only shows up as a red screen in a browser.
    //
    // Platform-specific code belongs behind a conditional import (see
    // lib/core/network/certificate_pinning.dart), and platform *questions*
    // belong to defaultTargetPlatform / kIsWeb.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith("import 'dart:io'") || line.startsWith('import "dart:io"')) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'dart:io throws on web. Use a conditional import, or '
          'defaultTargetPlatform/kIsWeb for platform checks.',
    );
  });
}
