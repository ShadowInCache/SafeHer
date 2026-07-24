import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_colors.dart';
import 'package:safeher_app/shared/components/charts/sa_donut_chart.dart';

import '../../../test_utils/widget_test_helpers.dart';

List<SaDonutSegment> _sampleSegments() => const [
  SaDonutSegment(label: 'Motion', value: 40, color: AppColors.violet500),
  SaDonutSegment(label: 'Audio', value: 35, color: AppColors.coral500),
  SaDonutSegment(label: 'Vision', value: 25, color: AppColors.success500),
];

void main() {
  group('SaDonutChart', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(SaDonutChart(segments: _sampleSegments()), brightness: Brightness.light));
      await tester.pump(const Duration(milliseconds: 1300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(SaDonutChart(segments: _sampleSegments())));
      await tester.pump(const Duration(milliseconds: 1300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles empty segments without exception', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaDonutChart(segments: [])));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        SaDonutChart(segments: _sampleSegments()),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(200, 200)),
        surfaceSize: const Size(200, 200),
      );
      await tester.pump(const Duration(milliseconds: 1300));
      await screenMatchesGolden(tester, 'sa_donut_chart_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        SaDonutChart(segments: _sampleSegments()),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(200, 200)),
        surfaceSize: const Size(200, 200),
      );
      await tester.pump(const Duration(milliseconds: 1300));
      await screenMatchesGolden(tester, 'sa_donut_chart_dark');
    });
  });
}
