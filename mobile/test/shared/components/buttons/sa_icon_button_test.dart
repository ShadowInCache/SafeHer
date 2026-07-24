import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/buttons/sa_icon_button.dart';
import 'package:safeher_app/shared/components/icons/sa_icon.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaIconButton', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          SaIconButton(
            icon: const SaIcon(SaIconGlyph.bell),
            semanticsLabel: 'Notifications',
            onPressed: () {},
          ),
          brightness: Brightness.light,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Notifications'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          SaIconButton(
            icon: const SaIcon(SaIconGlyph.bell),
            semanticsLabel: 'Notifications',
            onPressed: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrapWithTheme(
          SaIconButton(
            icon: const SaIcon(SaIconGlyph.bell),
            semanticsLabel: 'Notifications',
            onPressed: () => tapped = true,
          ),
        ),
      );
      await tester.tap(find.byType(SaIconButton));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SaIconButton(icon: const SaIcon(SaIconGlyph.bell), semanticsLabel: 'a', onPressed: () {}),
            const SizedBox(width: 12),
            SaIconButton(
              icon: const SaIcon(SaIconGlyph.search),
              semanticsLabel: 'b',
              variant: SaIconButtonVariant.filled,
              onPressed: () {},
            ),
            const SizedBox(width: 12),
            SaIconButton(
              icon: const SaIcon(SaIconGlyph.close),
              semanticsLabel: 'c',
              variant: SaIconButtonVariant.tonal,
              onPressed: () {},
            ),
          ],
        ),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(220, 100)),
        surfaceSize: const Size(220, 100),
      );
      await screenMatchesGolden(tester, 'sa_icon_button_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SaIconButton(icon: const SaIcon(SaIconGlyph.bell), semanticsLabel: 'a', onPressed: () {}),
            const SizedBox(width: 12),
            SaIconButton(
              icon: const SaIcon(SaIconGlyph.search),
              semanticsLabel: 'b',
              variant: SaIconButtonVariant.filled,
              onPressed: () {},
            ),
            const SizedBox(width: 12),
            SaIconButton(
              icon: const SaIcon(SaIconGlyph.close),
              semanticsLabel: 'c',
              variant: SaIconButtonVariant.tonal,
              onPressed: () {},
            ),
          ],
        ),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(220, 100)),
        surfaceSize: const Size(220, 100),
      );
      await screenMatchesGolden(tester, 'sa_icon_button_dark');
    });
  });
}
