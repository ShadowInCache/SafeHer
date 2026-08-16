import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/cards/sa_threat_gauge_card.dart';
import 'package:safeher_app/shared/components/charts/sa_threat_gauge.dart';

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

    testWidgets('centres the gauge when there are no component scores', (tester) async {
      // The layout the Home card actually shows today: no per-modality
      // scores, so the gauge used to sit left-aligned against empty space
      // with the timestamp orphaned underneath it.
      await tester.pumpWidget(
        wrapWithTheme(
          const SaThreatGaugeCard(score: 0.95, componentScores: [], lastUpdated: '5h ago'),
          surfaceSize: const Size(360, 260),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
      expect(find.text('Threat Level'), findsOneWidget);
      expect(find.text('5h ago'), findsOneWidget);
      expect(find.text('95'), findsOneWidget);
      expect(find.text('DANGER'), findsOneWidget);

      // Centred within the card rather than pinned to its left edge.
      final card = tester.getRect(find.byType(SaThreatGaugeCard));
      final gauge = tester.getRect(find.byType(SaThreatGauge));
      expect((gauge.center.dx - card.center.dx).abs(), lessThan(2));
    });

    testGoldens('golden - no component scores', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaThreatGaugeCard(score: 0.95, componentScores: [], lastUpdated: '5h ago'),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(360, 260)),
        surfaceSize: const Size(360, 260),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await screenMatchesGolden(
        tester,
        'sa_threat_gauge_card_no_components',
        // DANGER breathes on a repeat, so nothing settles.
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testWidgets('renders a waiting state instead of a gauge when score is null', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const SaThreatGaugeCard(score: null, componentScores: [], lastUpdated: null),
          surfaceSize: const Size(360, 200),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('Waiting for live device data'), findsOneWidget);
      expect(find.text('Motion'), findsNothing);
    });

    testGoldens('golden - waiting for data', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaThreatGaugeCard(score: null, componentScores: [], lastUpdated: null),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(360, 200)),
        surfaceSize: const Size(360, 200),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(tester, 'sa_threat_gauge_card_waiting');
    });
  });
}
