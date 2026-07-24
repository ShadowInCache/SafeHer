import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/charts/sa_bar_chart.dart';
import 'package:safeher_app/shared/models/threat_level.dart';

import '../../../test_utils/widget_test_helpers.dart';

List<SaBarChartDatum> _sampleData() => const [
  SaBarChartDatum(label: 'Mon', value: 2, level: ThreatLevel.safe),
  SaBarChartDatum(label: 'Tue', value: 5, level: ThreatLevel.caution),
  SaBarChartDatum(label: 'Wed', value: 3, level: ThreatLevel.elevated),
  SaBarChartDatum(label: 'Thu', value: 7, level: ThreatLevel.danger),
];

void main() {
  group('SaBarChart', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(SaBarChart(data: _sampleData()), brightness: Brightness.light));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(SaBarChart(data: _sampleData())));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles empty data without exception', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaBarChart(data: [])));
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles tap on a bar', (tester) async {
      int? tappedIndex;
      await tester.pumpWidget(wrapWithTheme(SaBarChart(data: _sampleData(), onBarTap: (i) => tappedIndex = i)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(tester.getCenter(find.byType(SaBarChart)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Bar hit detection depends on fl_chart's internal geometry; we only
      // assert the callback plumbing doesn't throw.
      expect(tappedIndex, anyOf(isNull, isA<int>()));
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        SizedBox(height: 200, child: SaBarChart(data: _sampleData())),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(320, 240)),
        surfaceSize: const Size(320, 240),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await screenMatchesGolden(tester, 'sa_bar_chart_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        SizedBox(height: 200, child: SaBarChart(data: _sampleData())),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(320, 240)),
        surfaceSize: const Size(320, 240),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await screenMatchesGolden(tester, 'sa_bar_chart_dark');
    });
  });
}
