import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/inputs/sa_search_bar.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaSearchBar', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaSearchBar(), brightness: Brightness.light));
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Voice search'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaSearchBar()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles tap on mic icon', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrapWithTheme(SaSearchBar(onMicTap: () => tapped = true)));
      await tester.tap(find.bySemanticsLabel('Voice search'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('icon morphs from mic to clear once text is entered', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaSearchBar()));
      await tester.enterText(find.byType(TextField), 'reports');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Clear search'), findsOneWidget);
      expect(find.bySemanticsLabel('Voice search'), findsNothing);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaSearchBar(),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(320, 80)),
        surfaceSize: const Size(320, 80),
      );
      await screenMatchesGolden(tester, 'sa_search_bar_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaSearchBar(),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(320, 80)),
        surfaceSize: const Size(320, 80),
      );
      await screenMatchesGolden(tester, 'sa_search_bar_dark');
    });
  });
}
