import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/shared/components/overlays/sa_confirm_dialog.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaConfirmDialog', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const SaConfirmDialog(title: 'Delete account', message: 'This is permanent.', confirmPhrase: 'DELETE'),
          brightness: Brightness.light,
          surfaceSize: const Size(400, 320),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Delete account'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const SaConfirmDialog(title: 'Delete account', message: 'This is permanent.', confirmPhrase: 'DELETE'),
          surfaceSize: const Size(400, 320),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('confirm button stays disabled until phrase matches exactly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SaConfirmDialog(title: 'Delete account', message: 'This is permanent.', confirmPhrase: 'DELETE'),
          ),
        ),
      );
      final deleteButton = find.text('Delete');
      expect(deleteButton, findsOneWidget);

      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.pump();
      await tester.tap(deleteButton);
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('showSaConfirmDialog returns true only after exact match + confirm', (tester) async {
      late Future<bool> resultFuture;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                resultFuture = showSaConfirmDialog(
                  context,
                  title: 'Delete account',
                  message: 'This is permanent.',
                  confirmPhrase: 'DELETE',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(await resultFuture, isTrue);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaConfirmDialog(title: 'Delete account', message: 'This is permanent.', confirmPhrase: 'DELETE'),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(400, 320)),
        surfaceSize: const Size(400, 320),
      );
      await screenMatchesGolden(tester, 'sa_confirm_dialog_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaConfirmDialog(title: 'Delete account', message: 'This is permanent.', confirmPhrase: 'DELETE'),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(400, 320)),
        surfaceSize: const Size(400, 320),
      );
      await screenMatchesGolden(tester, 'sa_confirm_dialog_dark');
    });
  });
}
