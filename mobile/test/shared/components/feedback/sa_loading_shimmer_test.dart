import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/feedback/sa_loading_shimmer.dart';

import '../../../test_utils/widget_test_helpers.dart';

Widget _placeholderShape() => Container(
  width: 200,
  height: 80,
  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
);

void main() {
  group('SaLoadingShimmer', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(SaLoadingShimmer(child: _placeholderShape()), brightness: Brightness.light),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(SaLoadingShimmer(child: _placeholderShape())));
      expect(tester.takeException(), isNull);
    });

    testWidgets('sweeps without throwing across pumps', (tester) async {
      await tester.pumpWidget(wrapWithTheme(SaLoadingShimmer(child: _placeholderShape())));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        SaLoadingShimmer(child: _placeholderShape()),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(240, 120)),
        surfaceSize: const Size(240, 120),
      );
      // Looping shimmer never converges under pumpAndSettle.
      await screenMatchesGolden(
        tester,
        'sa_loading_shimmer_light',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        SaLoadingShimmer(child: _placeholderShape()),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(240, 120)),
        surfaceSize: const Size(240, 120),
      );
      await screenMatchesGolden(
        tester,
        'sa_loading_shimmer_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });
  });
}
