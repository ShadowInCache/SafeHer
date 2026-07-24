import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/cards/sa_contact_card.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaContactCard', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const SaContactCard(name: 'Priya Sharma', relationship: 'Sister', priority: 1),
          brightness: Brightness.light,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Priya Sharma'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(const SaContactCard(name: 'Priya Sharma', relationship: 'Sister', priority: 1)),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrapWithTheme(
          SaContactCard(name: 'Priya Sharma', relationship: 'Sister', priority: 1, onTap: () => tapped = true),
        ),
      );
      await tester.tap(find.text('Priya Sharma'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaContactCard(name: 'Priya Sharma', relationship: 'Sister', priority: 1, confirmed: false),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(320, 100)),
        surfaceSize: const Size(320, 100),
      );
      await screenMatchesGolden(tester, 'sa_contact_card_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaContactCard(name: 'Priya Sharma', relationship: 'Sister', priority: 1, confirmed: false),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(320, 100)),
        surfaceSize: const Size(320, 100),
      );
      await screenMatchesGolden(tester, 'sa_contact_card_dark');
    });
  });
}
