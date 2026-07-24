import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/feedback/sa_signal_bars.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaSignalBars', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaSignalBars(strength: 2), brightness: Brightness.light));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaSignalBars(strength: 3)));
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Signal strength 3 of 3'), findsOneWidget);
    });

    testGoldens('golden - strengths light and dark', (tester) async {
      await tester.pumpWidgetBuilder(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SaSignalBars(strength: 0),
            SizedBox(width: 16),
            SaSignalBars(strength: 1),
            SizedBox(width: 16),
            SaSignalBars(strength: 2),
            SizedBox(width: 16),
            SaSignalBars(strength: 3),
          ],
        ),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(160, 40)),
        surfaceSize: const Size(160, 40),
      );
      await screenMatchesGolden(tester, 'sa_signal_bars_light');
    });
  });
}
