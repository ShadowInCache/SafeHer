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
            SaToastCard(
              title: 'Couldn’t sign you in',
              message: 'Incorrect email or password.',
              type: SaToastType.error,
            ),
            SizedBox(height: 8),
            SaToastCard(message: 'Alert cancelled', type: SaToastType.info),
          ],
        ),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(360, 260)),
        surfaceSize: const Size(360, 260),
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
            SaToastCard(
              title: 'Couldn’t sign you in',
              message: 'Incorrect email or password.',
              type: SaToastType.error,
            ),
            SizedBox(height: 8),
            SaToastCard(message: 'Alert cancelled', type: SaToastType.info),
          ],
        ),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(360, 260)),
        surfaceSize: const Size(360, 260),
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

    testWidgets('renders over an Overlay without losing its Material context', (tester) async {
      // Regression: the toast was inserted straight into the Overlay, which
      // provides no Material ancestor, so every line of text rendered with
      // Flutter's debug double-underline and no default style. It looked
      // broken on screen while every test still passed, because a golden of
      // SaToastCard alone was wrapped in a Scaffold that supplied one.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showSaToast(
                context,
                title: 'Couldn’t sign you in',
                message: 'Incorrect email or password.',
                type: SaToastType.error,
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

      final toastText = tester.widget<Text>(find.text('Incorrect email or password.'));
      final resolved = DefaultTextStyle.of(
        tester.element(find.text('Incorrect email or password.')),
      ).style.merge(toastText.style);

      expect(
        resolved.decoration,
        anyOf(isNull, TextDecoration.none),
        reason: 'A missing Material ancestor shows up as an underline here.',
      );
      expect(find.text('Couldn’t sign you in'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('a second toast replaces the first rather than stacking', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => Column(
              children: [
                ElevatedButton(
                  onPressed: () => showSaToast(context, message: 'First'),
                  child: const Text('One'),
                ),
                ElevatedButton(
                  onPressed: () => showSaToast(context, message: 'Second'),
                  child: const Text('Two'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('One'));
      await tester.pump();
      await tester.tap(find.text('Two'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // A burst of failures must not bury the screen under a stack of cards.
      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
