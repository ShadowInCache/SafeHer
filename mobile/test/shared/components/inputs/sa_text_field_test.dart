import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/inputs/sa_text_field.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaTextField', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaTextField(label: 'Email'), brightness: Brightness.light));
      expect(tester.takeException(), isNull);
      expect(find.text('Email'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaTextField(label: 'Email')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles tap and text entry', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(wrapWithTheme(SaTextField(label: 'Email', controller: controller)));
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'user@example.com');
      await tester.pump();
      expect(controller.text, 'user@example.com');
    });

    testWidgets('shows error text and shakes without throwing', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaTextField(label: 'Email', errorText: 'Email is required')));
      expect(find.text('Email is required'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaTextField(label: 'Email'),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(320, 100)),
        surfaceSize: const Size(320, 100),
      );
      await screenMatchesGolden(tester, 'sa_text_field_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaTextField(label: 'Email'),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(320, 100)),
        surfaceSize: const Size(320, 100),
      );
      await screenMatchesGolden(tester, 'sa_text_field_dark');
    });
  });
}
