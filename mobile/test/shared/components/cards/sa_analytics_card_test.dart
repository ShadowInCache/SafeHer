import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/cards/sa_analytics_card.dart';
import 'package:safeher_app/shared/components/charts/sa_sparkline.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaAnalyticsCard', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          SaAnalyticsCard(title: 'Total Incidents', chart: SaSparkline(values: const [1, 3, 2, 5])),
          brightness: Brightness.light,
          surfaceSize: const Size(320, 200),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      expect(find.text('Total Incidents'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          SaAnalyticsCard(title: 'Total Incidents', chart: SaSparkline(values: const [1, 3, 2, 5])),
          surfaceSize: const Size(320, 200),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles tap on action link', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrapWithTheme(
          SaAnalyticsCard(
            title: 'Total Incidents',
            chart: SaSparkline(values: const [1, 3, 2, 5]),
            action: 'View all',
            onActionTap: () => tapped = true,
          ),
          surfaceSize: const Size(320, 200),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('View all'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        SaAnalyticsCard(
          title: 'Total Incidents',
          chart: SaSparkline(values: const [1, 3, 2, 5, 4, 7]),
          action: 'View all',
          onActionTap: () {},
        ),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(320, 200)),
        surfaceSize: const Size(320, 200),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await screenMatchesGolden(tester, 'sa_analytics_card_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        SaAnalyticsCard(
          title: 'Total Incidents',
          chart: SaSparkline(values: const [1, 3, 2, 5, 4, 7]),
          action: 'View all',
          onActionTap: () {},
        ),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(320, 200)),
        surfaceSize: const Size(320, 200),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await screenMatchesGolden(tester, 'sa_analytics_card_dark');
    });
  });
}
