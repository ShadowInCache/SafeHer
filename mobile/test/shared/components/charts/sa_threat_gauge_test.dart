import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/charts/sa_threat_gauge.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaThreatGauge', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaThreatGauge(score: 0.3), brightness: Brightness.light));
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaThreatGauge(score: 0.3)));
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.takeException(), isNull);
    });

    testWidgets('animates smoothly when score changes', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaThreatGauge(score: 0.2)));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpWidget(wrapWithTheme(const SaThreatGauge(score: 0.85)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('85'), findsOneWidget);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaThreatGauge(score: 0.35),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(220, 220)),
        surfaceSize: const Size(220, 220),
      );
      await tester.pump(const Duration(milliseconds: 900));
      await screenMatchesGolden(tester, 'sa_threat_gauge_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaThreatGauge(score: 0.82),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(220, 220)),
        surfaceSize: const Size(220, 220),
      );
      await tester.pump(const Duration(milliseconds: 900));
      await screenMatchesGolden(tester, 'sa_threat_gauge_dark');
    });
  });
}
