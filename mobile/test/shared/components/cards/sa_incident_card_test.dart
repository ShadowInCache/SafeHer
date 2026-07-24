import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/cards/sa_incident_card.dart';
import 'package:safeher_app/shared/models/threat_level.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaIncidentCard', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const SaIncidentCard(
            date: 'Jul 20',
            type: 'Motion + Audio',
            level: ThreatLevel.danger,
            summarySnippet: 'Screaming detected with rapid movement.',
          ),
          brightness: Brightness.light,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Motion + Audio'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const SaIncidentCard(
            date: 'Jul 20',
            type: 'Motion + Audio',
            level: ThreatLevel.danger,
            summarySnippet: 'Screaming detected with rapid movement.',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrapWithTheme(
          SaIncidentCard(
            date: 'Jul 20',
            type: 'Motion + Audio',
            level: ThreatLevel.danger,
            summarySnippet: 'Screaming detected with rapid movement.',
            onTap: () => tapped = true,
          ),
        ),
      );
      await tester.tap(find.byType(SaIncidentCard));
      // ThreatLevel.danger drives an indefinitely-pulsing chip; pump a
      // fixed amount instead of pumpAndSettle, which would never converge.
      await tester.pump(const Duration(milliseconds: 200));
      expect(tapped, isTrue);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaIncidentCard(
          date: 'Jul 20',
          type: 'Motion + Audio',
          level: ThreatLevel.danger,
          summarySnippet: 'Screaming detected with rapid movement.',
        ),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(340, 100)),
        surfaceSize: const Size(340, 100),
      );
      // ThreatLevel.danger drives an indefinitely-pulsing SaThreatChip; use
      // a fixed pump instead of pumpAndSettle, which would never converge.
      await screenMatchesGolden(
        tester,
        'sa_incident_card_light',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaIncidentCard(
          date: 'Jul 20',
          type: 'Motion + Audio',
          level: ThreatLevel.danger,
          summarySnippet: 'Screaming detected with rapid movement.',
        ),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(340, 100)),
        surfaceSize: const Size(340, 100),
      );
      await screenMatchesGolden(
        tester,
        'sa_incident_card_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });
  });
}
