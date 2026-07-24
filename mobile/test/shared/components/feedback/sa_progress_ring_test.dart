import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/feedback/sa_progress_ring.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaProgressRing', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(const SaProgressRing(progress: 0.72, label: '72'), brightness: Brightness.light),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('72'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaProgressRing(progress: 0.72, label: '72')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('clamps out-of-range progress without exception', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaProgressRing(progress: 1.6)));
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Progress 100 percent'), findsOneWidget);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaProgressRing(progress: 0.65, label: '7d'),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(120, 120)),
        surfaceSize: const Size(120, 120),
      );
      await screenMatchesGolden(tester, 'sa_progress_ring_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaProgressRing(progress: 0.65, label: '7d'),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(120, 120)),
        surfaceSize: const Size(120, 120),
      );
      await screenMatchesGolden(tester, 'sa_progress_ring_dark');
    });
  });
}
