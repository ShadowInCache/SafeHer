import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/shared/components/overlays/sa_bottom_sheet.dart';

import '../../../test_utils/widget_test_helpers.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

void main() {
  group('SaBottomSheet', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(const SaBottomSheet(child: Text('Sheet content')), brightness: Brightness.light),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Sheet content'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaBottomSheet(child: Text('Sheet content'))));
      expect(tester.takeException(), isNull);
    });

    testWidgets('showSaBottomSheet presents and dismisses content', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
    // Mirrors main.dart's shell so screens render over the same ambient
    // field users see; the scaffold background is transparent by design.
    builder: (context, child) =>
        SaAmbientBackground(child: child ?? const SizedBox.shrink()),
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showSaBottomSheet<void>(context, builder: (ctx) => const Text('Sheet body')),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Sheet body'), findsOneWidget);

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('Sheet body'), findsNothing);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaBottomSheet(child: Text('Sheet content')),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(320, 160)),
        surfaceSize: const Size(320, 160),
      );
      await screenMatchesGolden(tester, 'sa_bottom_sheet_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaBottomSheet(child: Text('Sheet content')),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(320, 160)),
        surfaceSize: const Size(320, 160),
      );
      await screenMatchesGolden(tester, 'sa_bottom_sheet_dark');
    });
  });
}
