import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/cards/sa_threat_gauge_card.dart';

import '../../../test_utils/widget_test_helpers.dart';

List<SaComponentScore> _components() => const [
  SaComponentScore(label: 'Motion', score: 0.3),
  SaComponentScore(label: 'Audio', score: 0.6),
  SaComponentScore(label: 'Vision', score: 0.1),
];

void main() {
  group('SaThreatGaugeCard', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          SaThreatGaugeCard(score: 0.35, componentScores: _components(), lastUpdated: '2m ago'),
          brightness: Brightness.light,
          surfaceSize: const Size(360, 260),
        ),
      );
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.takeException(), isNull);
      expect(find.text('Motion'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          SaThreatGaugeCard(score: 0.35, componentScores: _components(), lastUpdated: '2m ago'),
          surfaceSize: const Size(360, 260),
        ),
      );
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.takeException(), isNull);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        SaThreatGaugeCard(score: 0.42, componentScores: _components(), lastUpdated: '2m ago'),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(360, 260)),
        surfaceSize: const Size(360, 260),
      );
      await tester.pump(const Duration(milliseconds: 900));
      await screenMatchesGolden(tester, 'sa_threat_gauge_card_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        SaThreatGaugeCard(score: 0.42, componentScores: _components(), lastUpdated: '2m ago'),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(360, 260)),
        surfaceSize: const Size(360, 260),
      );
      await tester.pump(const Duration(milliseconds: 900));
      await screenMatchesGolden(tester, 'sa_threat_gauge_card_dark');
    });
  });
}
