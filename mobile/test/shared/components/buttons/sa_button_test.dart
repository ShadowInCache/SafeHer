import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/buttons/sa_button.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaButton', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          SaButton(label: 'Sign In', onPressed: () {}),
          brightness: Brightness.light,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          SaButton(label: 'Sign In', onPressed: () {}),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('handles tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrapWithTheme(SaButton(label: 'Continue', onPressed: () => tapped = true)),
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('disabled button does not fire onPressed', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrapWithTheme(SaButton(label: 'Continue', onPressed: null)),
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(tapped, isFalse);
    });

    testWidgets('loading state hides label and shows spinner', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(SaButton(label: 'Continue', onPressed: () {}, isLoading: true)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
    });

    testWidgets('danger button with confirmRequired arms before firing', (tester) async {
      var confirmedCount = 0;
      await tester.pumpWidget(
        wrapWithTheme(
          SaButton(
            label: 'Delete Account',
            variant: SaButtonVariant.danger,
            confirmRequired: true,
            onPressed: () => confirmedCount++,
          ),
        ),
      );
      await tester.tap(find.text('Delete Account'));
      await tester.pump();
      expect(confirmedCount, 0);
      expect(find.text('Tap again to confirm'), findsOneWidget);

      await tester.tap(find.text('Tap again to confirm'));
      await tester.pump();
      expect(confirmedCount, 1);
      // Flush the arm-reset timer so it doesn't leak past test teardown.
      await tester.pump(const Duration(seconds: 3));
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SaButton(label: 'Primary', onPressed: () {}),
            const SizedBox(height: 12),
            SaButton(label: 'Secondary', variant: SaButtonVariant.secondary, onPressed: () {}),
            const SizedBox(height: 12),
            SaButton(label: 'Ghost', variant: SaButtonVariant.ghost, onPressed: () {}),
            const SizedBox(height: 12),
            SaButton(label: 'Danger', variant: SaButtonVariant.danger, onPressed: () {}),
            const SizedBox(height: 12),
            SaButton(label: 'Disabled', onPressed: null),
          ],
        ),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(300, 420)),
        surfaceSize: const Size(300, 420),
      );
      await screenMatchesGolden(tester, 'sa_button_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SaButton(label: 'Primary', onPressed: () {}),
            const SizedBox(height: 12),
            SaButton(label: 'Secondary', variant: SaButtonVariant.secondary, onPressed: () {}),
            const SizedBox(height: 12),
            SaButton(label: 'Ghost', variant: SaButtonVariant.ghost, onPressed: () {}),
            const SizedBox(height: 12),
            SaButton(label: 'Danger', variant: SaButtonVariant.danger, onPressed: () {}),
            const SizedBox(height: 12),
            SaButton(label: 'Disabled', onPressed: null),
          ],
        ),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(300, 420)),
        surfaceSize: const Size(300, 420),
      );
      await screenMatchesGolden(tester, 'sa_button_dark');
    });
  });
}
