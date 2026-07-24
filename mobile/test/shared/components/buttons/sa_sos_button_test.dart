import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/buttons/sa_sos_button.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaSOSButton', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(SaSOSButton(onConfirmed: () {}), brightness: Brightness.light),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('SOS'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(SaSOSButton(onConfirmed: () {})));
      expect(tester.takeException(), isNull);
      expect(find.text('SOS'), findsOneWidget);
    });

    testWidgets('confirms after holding for holdDuration', (tester) async {
      var confirmed = false;
      await tester.pumpWidget(
        wrapWithTheme(
          SaSOSButton(
            onConfirmed: () => confirmed = true,
            holdDuration: const Duration(milliseconds: 300),
          ),
        ),
      );

      final gesture = await tester.startGesture(tester.getCenter(find.byType(SaSOSButton)));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 400));
      expect(confirmed, isTrue);
      await gesture.up();
    });

    testWidgets('releasing before holdDuration does not confirm', (tester) async {
      var confirmed = false;
      await tester.pumpWidget(
        wrapWithTheme(
          SaSOSButton(
            onConfirmed: () => confirmed = true,
            holdDuration: const Duration(milliseconds: 600),
          ),
        ),
      );

      final gesture = await tester.startGesture(tester.getCenter(find.byType(SaSOSButton)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(confirmed, isFalse);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        SaSOSButton(onConfirmed: () {}),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(220, 220)),
        surfaceSize: const Size(220, 220),
      );
      // The breathing animation loops forever; use a fixed pump instead of
      // pumpAndSettle (which would never converge) to capture a frame.
      await screenMatchesGolden(
        tester,
        'sa_sos_button_light',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        SaSOSButton(onConfirmed: () {}),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(220, 220)),
        surfaceSize: const Size(220, 220),
      );
      await screenMatchesGolden(
        tester,
        'sa_sos_button_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });
  });
}
