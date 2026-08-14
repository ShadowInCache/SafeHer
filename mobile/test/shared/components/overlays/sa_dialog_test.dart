import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/shared/components/overlays/sa_dialog.dart';

import '../../../test_utils/widget_test_helpers.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

void main() {
  group('SaDialog', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          SaDialog(
            title: 'Delete report?',
            message: 'This cannot be undone.',
            actions: [SaDialogAction(label: 'Delete', onPressed: () {}, isDestructive: true)],
          ),
          brightness: Brightness.light,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Delete report?'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          SaDialog(title: 'Delete report?', message: 'This cannot be undone.'),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles tap on action', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrapWithTheme(
          SaDialog(title: 'Delete report?', actions: [SaDialogAction(label: 'Delete', onPressed: () => tapped = true)]),
        ),
      );
      await tester.tap(find.text('Delete'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('showSaDialog presents and dismisses', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
    // Mirrors main.dart's shell so screens render over the same ambient
    // field users see; the scaffold background is transparent by design.
    builder: (context, child) =>
        SaAmbientBackground(child: child ?? const SizedBox.shrink()),
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showSaDialog<void>(context, title: 'Are you sure?'),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Are you sure?'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Are you sure?'), findsNothing);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        SaDialog(
          title: 'Delete report?',
          message: 'This cannot be undone.',
          actions: [
            SaDialogAction(label: 'Cancel', onPressed: () {}),
            SaDialogAction(label: 'Delete', onPressed: () {}, isDestructive: true),
          ],
        ),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(400, 220)),
        surfaceSize: const Size(400, 220),
      );
      await screenMatchesGolden(tester, 'sa_dialog_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        SaDialog(
          title: 'Delete report?',
          message: 'This cannot be undone.',
          actions: [
            SaDialogAction(label: 'Cancel', onPressed: () {}),
            SaDialogAction(label: 'Delete', onPressed: () {}, isDestructive: true),
          ],
        ),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(400, 220)),
        surfaceSize: const Size(400, 220),
      );
      await screenMatchesGolden(tester, 'sa_dialog_dark');
    });
  });
}
