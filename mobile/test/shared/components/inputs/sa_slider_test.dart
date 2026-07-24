import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/inputs/sa_slider.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaSlider', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(SaSlider(value: 0.5, onChanged: (_) {}), brightness: Brightness.light),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(SaSlider(value: 0.5, onChanged: (_) {})));
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles drag to change value', (tester) async {
      double? changed;
      await tester.pumpWidget(
        wrapWithTheme(
          SaSlider(value: 0.5, onChanged: (v) => changed = v),
          surfaceSize: const Size(300, 100),
        ),
      );
      await tester.drag(find.byType(Slider), const Offset(50, 0));
      await tester.pump();
      expect(changed, isNotNull);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        SaSlider(value: 0.65, onChanged: (_) {}),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(300, 60)),
        surfaceSize: const Size(300, 60),
      );
      await screenMatchesGolden(tester, 'sa_slider_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        SaSlider(value: 0.65, onChanged: (_) {}),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(300, 60)),
        surfaceSize: const Size(300, 60),
      );
      await screenMatchesGolden(tester, 'sa_slider_dark');
    });
  });
}
