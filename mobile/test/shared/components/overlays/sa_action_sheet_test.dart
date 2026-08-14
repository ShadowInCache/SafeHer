import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/shared/components/overlays/sa_action_sheet.dart';

import '../../../test_utils/widget_test_helpers.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

void main() {
  group('SaActionSheetContent', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          SaActionSheetContent(
            title: 'Report options',
            items: [
              SaActionSheetItem(label: 'Export PDF', onTap: () {}),
              SaActionSheetItem(label: 'Delete', onTap: () {}, isDestructive: true),
            ],
          ),
          brightness: Brightness.light,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Export PDF'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          SaActionSheetContent(items: [SaActionSheetItem(label: 'Export PDF', onTap: () {})]),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles tap on item', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrapWithTheme(
          SaActionSheetContent(items: [SaActionSheetItem(label: 'Export PDF', onTap: () => tapped = true)]),
        ),
      );
      await tester.tap(find.text('Export PDF'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('showSaActionSheet presents content', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
    // Mirrors main.dart's shell so screens render over the same ambient
    // field users see; the scaffold background is transparent by design.
    builder: (context, child) =>
        SaAmbientBackground(child: child ?? const SizedBox.shrink()),
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showSaActionSheet(
                context,
                items: [SaActionSheetItem(label: 'Share', onTap: () {})],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Share'), findsOneWidget);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        SaActionSheetContent(
          title: 'Report options',
          items: [
            SaActionSheetItem(label: 'Export PDF', onTap: () {}),
            SaActionSheetItem(label: 'Share Secure Link', onTap: () {}),
            SaActionSheetItem(label: 'Delete', onTap: () {}, isDestructive: true),
          ],
        ),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(320, 220)),
        surfaceSize: const Size(320, 220),
      );
      await screenMatchesGolden(tester, 'sa_action_sheet_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        SaActionSheetContent(
          title: 'Report options',
          items: [
            SaActionSheetItem(label: 'Export PDF', onTap: () {}),
            SaActionSheetItem(label: 'Share Secure Link', onTap: () {}),
            SaActionSheetItem(label: 'Delete', onTap: () {}, isDestructive: true),
          ],
        ),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(320, 220)),
        surfaceSize: const Size(320, 220),
      );
      await screenMatchesGolden(tester, 'sa_action_sheet_dark');
    });
  });
}
