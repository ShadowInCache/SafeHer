import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/cards/sa_card.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaCard', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaCard(child: Text('content')), brightness: Brightness.light));
      expect(tester.takeException(), isNull);
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaCard(child: Text('content'))));
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrapWithTheme(SaCard(onTap: () => tapped = true, child: const Text('content'))));
      await tester.tap(find.text('content'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        const SizedBox(width: 240, height: 120, child: SaCard(child: Text('Glass card'))),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(280, 160)),
        surfaceSize: const Size(280, 160),
      );
      await screenMatchesGolden(tester, 'sa_card_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        const SizedBox(width: 240, height: 120, child: SaCard(child: Text('Glass card'))),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(280, 160)),
        surfaceSize: const Size(280, 160),
      );
      await screenMatchesGolden(tester, 'sa_card_dark');
    });
  });
}
