import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/feedback/sa_empty_state.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaEmptyState', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const SaEmptyState(title: 'No results', body: 'Try a different search term.'),
          brightness: Brightness.light,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('No results'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(const SaEmptyState(title: 'No results', body: 'Try a different search term.')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles tap on CTA', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrapWithTheme(
          SaEmptyState(
            title: 'No contacts yet',
            body: 'Add someone you trust.',
            ctaLabel: 'Add Contact',
            onCtaTap: () => tapped = true,
          ),
        ),
      );
      await tester.tap(find.text('Add Contact'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaEmptyState(
          title: 'No results',
          body: 'Try a different search term.',
          ctaLabel: 'Clear Search',
        ),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(320, 320)),
        surfaceSize: const Size(320, 320),
      );
      await screenMatchesGolden(tester, 'sa_empty_state_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaEmptyState(
          title: 'No results',
          body: 'Try a different search term.',
          ctaLabel: 'Clear Search',
        ),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(320, 320)),
        surfaceSize: const Size(320, 320),
      );
      await screenMatchesGolden(tester, 'sa_empty_state_dark');
    });
  });
}
