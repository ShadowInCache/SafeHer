import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/cards/sa_alert_card.dart';
import 'package:safeher_app/shared/models/threat_level.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaAlertCard', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const SaAlertCard(
            title: 'Elevated motion detected',
            timestamp: '2m ago',
            level: ThreatLevel.elevated,
            summary: 'Sudden acceleration spike near Elm Street.',
          ),
          brightness: Brightness.light,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Elevated motion detected'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const SaAlertCard(
            title: 'Elevated motion detected',
            timestamp: '2m ago',
            level: ThreatLevel.elevated,
            summary: 'Sudden acceleration spike near Elm Street.',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrapWithTheme(
          SaAlertCard(
            title: 'Elevated motion detected',
            timestamp: '2m ago',
            level: ThreatLevel.elevated,
            summary: 'Sudden acceleration spike near Elm Street.',
            onTap: () => tapped = true,
          ),
        ),
      );
      await tester.tap(find.text('Elevated motion detected'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaAlertCard(
          title: 'Elevated motion detected',
          timestamp: '2m ago',
          level: ThreatLevel.elevated,
          summary: 'Sudden acceleration spike near Elm Street.',
        ),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(320, 180)),
        surfaceSize: const Size(320, 180),
      );
      await screenMatchesGolden(tester, 'sa_alert_card_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaAlertCard(
          title: 'Elevated motion detected',
          timestamp: '2m ago',
          level: ThreatLevel.elevated,
          summary: 'Sudden acceleration spike near Elm Street.',
        ),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(320, 180)),
        surfaceSize: const Size(320, 180),
      );
      await screenMatchesGolden(tester, 'sa_alert_card_dark');
    });
  });
}
