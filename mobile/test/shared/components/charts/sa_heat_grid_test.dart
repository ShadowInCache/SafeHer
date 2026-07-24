import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/charts/sa_heat_grid.dart';

import '../../../test_utils/widget_test_helpers.dart';

List<List<double>> _sampleGrid() => [
  [0.1, 0.4, 0.8, 0.2],
  [0.3, 0.9, 0.5, 0.0],
  [0.0, 0.2, 0.6, 0.7],
];

void main() {
  group('SaHeatGrid', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(SaHeatGrid(grid: _sampleGrid()), brightness: Brightness.light));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(SaHeatGrid(grid: _sampleGrid())));
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles empty grid without exception', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaHeatGrid(grid: [])));
      expect(tester.takeException(), isNull);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        SizedBox(height: 140, child: SaHeatGrid(grid: _sampleGrid())),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(300, 160)),
        surfaceSize: const Size(300, 160),
      );
      await screenMatchesGolden(tester, 'sa_heat_grid_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        SizedBox(height: 140, child: SaHeatGrid(grid: _sampleGrid())),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(300, 160)),
        surfaceSize: const Size(300, 160),
      );
      await screenMatchesGolden(tester, 'sa_heat_grid_dark');
    });
  });
}
