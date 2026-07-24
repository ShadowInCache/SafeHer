import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/cards/sa_stat_card.dart';
import 'package:safeher_app/shared/components/icons/sa_icon.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaStatCard', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const SaStatCard(value: '128h', label: 'Safe Hours', trend: SaTrendDirection.up, icon: SaIconGlyph.shield),
          brightness: Brightness.light,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('128h'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const SaStatCard(value: '128h', label: 'Safe Hours', trend: SaTrendDirection.up, icon: SaIconGlyph.shield),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaStatCard(value: '128h', label: 'Safe Hours', trend: SaTrendDirection.up, icon: SaIconGlyph.shield),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(180, 140)),
        surfaceSize: const Size(180, 140),
      );
      await screenMatchesGolden(tester, 'sa_stat_card_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaStatCard(value: '128h', label: 'Safe Hours', trend: SaTrendDirection.up, icon: SaIconGlyph.shield),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(180, 140)),
        surfaceSize: const Size(180, 140),
      );
      await screenMatchesGolden(tester, 'sa_stat_card_dark');
    });
  });
}
