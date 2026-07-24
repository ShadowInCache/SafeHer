import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/feedback/sa_threat_chip.dart';
import 'package:safeher_app/shared/models/threat_level.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaThreatChip', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaThreatChip(level: ThreatLevel.safe), brightness: Brightness.light));
      expect(tester.takeException(), isNull);
      expect(find.text('SAFE'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaThreatChip(level: ThreatLevel.danger)));
      expect(tester.takeException(), isNull);
      expect(find.text('DANGER'), findsOneWidget);
    });

    testWidgets('danger level pulses without throwing across pumps', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaThreatChip(level: ThreatLevel.danger)));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });

    testGoldens('golden - all levels light', (tester) async {
      await tester.pumpWidgetBuilder(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SaThreatChip(level: ThreatLevel.safe),
            SizedBox(height: 8),
            SaThreatChip(level: ThreatLevel.caution),
            SizedBox(height: 8),
            SaThreatChip(level: ThreatLevel.elevated),
            SizedBox(height: 8),
            SaThreatChip(level: ThreatLevel.danger),
          ],
        ),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(160, 180)),
        surfaceSize: const Size(160, 180),
      );
      // The DANGER chip pulses forever; use a fixed pump instead of
      // pumpAndSettle (which would never converge) to capture a frame.
      await screenMatchesGolden(
        tester,
        'sa_threat_chip_light',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testGoldens('golden - all levels dark', (tester) async {
      await tester.pumpWidgetBuilder(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SaThreatChip(level: ThreatLevel.safe),
            SizedBox(height: 8),
            SaThreatChip(level: ThreatLevel.caution),
            SizedBox(height: 8),
            SaThreatChip(level: ThreatLevel.elevated),
            SizedBox(height: 8),
            SaThreatChip(level: ThreatLevel.danger),
          ],
        ),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(160, 180)),
        surfaceSize: const Size(160, 180),
      );
      await screenMatchesGolden(
        tester,
        'sa_threat_chip_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });
  });
}
