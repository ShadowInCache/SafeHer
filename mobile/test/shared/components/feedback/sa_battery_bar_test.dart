import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/feedback/sa_battery_bar.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaBatteryBar', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaBatteryBar(percent: 0.8), brightness: Brightness.light));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaBatteryBar(percent: 0.15)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('clamps out-of-range percent without exception', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaBatteryBar(percent: 1.4)));
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Battery 100 percent'), findsOneWidget);
    });

    testGoldens('golden - thresholds light and dark', (tester) async {
      await tester.pumpWidgetBuilder(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 160, child: SaBatteryBar(percent: 0.85)),
            SizedBox(height: 12),
            SizedBox(width: 160, child: SaBatteryBar(percent: 0.15)),
            SizedBox(height: 12),
            SizedBox(width: 160, child: SaBatteryBar(percent: 0.05)),
          ],
        ),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(200, 100)),
        surfaceSize: const Size(200, 100),
      );
      await screenMatchesGolden(tester, 'sa_battery_bar_light');
    });
  });
}
