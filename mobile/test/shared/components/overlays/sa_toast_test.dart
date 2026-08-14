import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/shared/components/overlays/sa_toast.dart';

import '../../../test_utils/widget_test_helpers.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

void main() {
  group('SaToastCard', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(const SaToastCard(message: 'OTP sent!', type: SaToastType.success), brightness: Brightness.light),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('OTP sent!'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaToastCard(message: 'OTP sent!', type: SaToastType.success)));
      expect(tester.takeException(), isNull);
    });

    testGoldens('golden - all types light', (tester) async {
      await tester.pumpWidgetBuilder(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SaToastCard(message: 'OTP sent!', type: SaToastType.success),
            SizedBox(height: 8),
            SaToastCard(message: 'Wrong credentials', type: SaToastType.error),
            SizedBox(height: 8),
            SaToastCard(message: 'Alert cancelled', type: SaToastType.info),
          ],
        ),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(320, 200)),
        surfaceSize: const Size(320, 200),
      );
      await screenMatchesGolden(tester, 'sa_toast_card_light');
    });

    testGoldens('golden - all types dark', (tester) async {
      await tester.pumpWidgetBuilder(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SaToastCard(message: 'OTP sent!', type: SaToastType.success),
            SizedBox(height: 8),
            SaToastCard(message: 'Wrong credentials', type: SaToastType.error),
            SizedBox(height: 8),
            SaToastCard(message: 'Alert cancelled', type: SaToastType.info),
          ],
        ),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(320, 200)),
        surfaceSize: const Size(320, 200),
      );
      await screenMatchesGolden(tester, 'sa_toast_card_dark');
    });
  });

  group('showSaToast', () {
    testWidgets('inserts and auto-dismisses after duration', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
    // Mirrors main.dart's shell so screens render over the same ambient
    // field users see; the scaffold background is transparent by design.
    builder: (context, child) =>
        SaAmbientBackground(child: child ?? const SizedBox.shrink()),
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showSaToast(
                context,
                message: 'Alert sent',
                duration: const Duration(milliseconds: 300),
              ),
              child: const Text('Trigger'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Trigger'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Alert sent'), findsOneWidget);

      // Flush the toast's own reverse-animation timer and the overlay's
      // removal timer (duration + 250ms) so nothing leaks past teardown.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Alert sent'), findsNothing);
    });
  });
}
