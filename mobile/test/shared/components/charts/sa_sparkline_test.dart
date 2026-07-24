import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/charts/sa_sparkline.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaSparkline', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(SaSparkline(values: const [1, 3, 2, 5, 4, 6]), brightness: Brightness.light),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(SaSparkline(values: const [1, 3, 2, 5, 4, 6])));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles empty values without exception', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaSparkline(values: [])));
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles all-equal values without exception', (tester) async {
      await tester.pumpWidget(wrapWithTheme(SaSparkline(values: const [4, 4, 4, 4])));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        SizedBox(width: 240, child: SaSparkline(values: const [2, 4, 3, 6, 5, 8, 7])),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(260, 80)),
        surfaceSize: const Size(260, 80),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await screenMatchesGolden(tester, 'sa_sparkline_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        SizedBox(width: 240, child: SaSparkline(values: const [2, 4, 3, 6, 5, 8, 7])),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(260, 80)),
        surfaceSize: const Size(260, 80),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await screenMatchesGolden(tester, 'sa_sparkline_dark');
    });
  });
}
