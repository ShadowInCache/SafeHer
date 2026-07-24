import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/cards/sa_device_card.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaDeviceCard', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const SaDeviceCard(name: 'Smart Ring', batteryPercent: 0.72, signalStrength: 2, isOnline: true),
          brightness: Brightness.light,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Smart Ring'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const SaDeviceCard(name: 'Smart Ring', batteryPercent: 0.72, signalStrength: 2, isOnline: true),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrapWithTheme(
          SaDeviceCard(
            name: 'Smart Ring',
            batteryPercent: 0.72,
            signalStrength: 2,
            isOnline: true,
            onTap: () => tapped = true,
          ),
        ),
      );
      await tester.tap(find.text('Smart Ring'));
      // isOnline:true drives an indefinitely-pulsing status dot; pump a
      // fixed amount instead of pumpAndSettle, which would never converge.
      await tester.pump(const Duration(milliseconds: 200));
      expect(tapped, isTrue);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaDeviceCard(name: 'Smart Ring', batteryPercent: 0.72, signalStrength: 2, isOnline: true),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(180, 200)),
        surfaceSize: const Size(180, 200),
      );
      // isOnline:true drives an indefinitely-pulsing SaStatusDot; use a
      // fixed pump instead of pumpAndSettle, which would never converge.
      await screenMatchesGolden(
        tester,
        'sa_device_card_light',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaDeviceCard(name: 'Smart Ring', batteryPercent: 0.72, signalStrength: 2, isOnline: true),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(180, 200)),
        surfaceSize: const Size(180, 200),
      );
      await screenMatchesGolden(
        tester,
        'sa_device_card_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });
  });
}
