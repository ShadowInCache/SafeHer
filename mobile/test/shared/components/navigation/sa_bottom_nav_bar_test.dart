import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/navigation/sa_bottom_nav_bar.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaBottomNavBar', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          SaBottomNavBar(currentTab: SaNavTab.home, onTabSelected: (_) {}, onSosTap: () {}),
          brightness: Brightness.light,
          surfaceSize: const Size(360, 300),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          SaBottomNavBar(currentTab: SaNavTab.home, onTabSelected: (_) {}, onSosTap: () {}),
          surfaceSize: const Size(360, 300),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles tap on a tab', (tester) async {
      SaNavTab? selected;
      await tester.pumpWidget(
        wrapWithTheme(
          SaBottomNavBar(currentTab: SaNavTab.home, onTabSelected: (t) => selected = t, onSosTap: () {}),
          surfaceSize: const Size(360, 300),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Dashboard'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(selected, SaNavTab.dashboard);
    });

    testWidgets('handles tap on SOS FAB', (tester) async {
      // wrapWithTheme's MediaQuery override only informs layout, it doesn't
      // resize the real test viewport — without this, hit-testing runs
      // against the default 800x600 surface and can miss small widgets.
      await tester.binding.setSurfaceSize(const Size(360, 300));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var tapped = false;
      await tester.pumpWidget(
        wrapWithTheme(
          SaBottomNavBar(currentTab: SaNavTab.home, onTabSelected: (_) {}, onSosTap: () => tapped = true),
          surfaceSize: const Size(360, 300),
        ),
      );
      // Let the initial MaterialApp route transition finish before tapping
      // (can't pumpAndSettle: the FAB's breathing animation loops forever).
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.bySemanticsLabel('SOS emergency'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('translates offscreen when visible is false', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          SaBottomNavBar(currentTab: SaNavTab.home, onTabSelected: (_) {}, onSosTap: () {}, visible: false),
          surfaceSize: const Size(360, 300),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        SaBottomNavBar(currentTab: SaNavTab.monitor, onTabSelected: (_) {}, onSosTap: () {}),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(360, 300)),
        surfaceSize: const Size(360, 300),
      );
      // Breathing SOS FAB loops forever; fixed pump instead of settle.
      await screenMatchesGolden(
        tester,
        'sa_bottom_nav_bar_light',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        SaBottomNavBar(currentTab: SaNavTab.monitor, onTabSelected: (_) {}, onSosTap: () {}),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(360, 300)),
        surfaceSize: const Size(360, 300),
      );
      await screenMatchesGolden(
        tester,
        'sa_bottom_nav_bar_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });
  });
}
