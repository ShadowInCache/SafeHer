import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/inputs/sa_password_field.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('computePasswordStrength', () {
    test('short password is weak', () {
      expect(computePasswordStrength('abc'), 1);
    });

    test('8+ chars no special is fair', () {
      expect(computePasswordStrength('password'), 2);
    });

    test('8+ chars with special is good', () {
      expect(computePasswordStrength('password!'), 3);
    });

    test('12+ mixed case digit special is strong', () {
      expect(computePasswordStrength('P@ssw0rdLong!'), 4);
    });
  });

  group('SaPasswordField', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaPasswordField(label: 'Password'), brightness: Brightness.light));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaPasswordField(label: 'Password')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles tap to toggle obscure text', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaPasswordField(label: 'Password')));
      expect(find.bySemanticsLabel('Show password'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Show password'));
      await tester.pump();
      expect(find.bySemanticsLabel('Hide password'), findsOneWidget);
    });

    testWidgets('strength bar updates as user types', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaPasswordField(label: 'Password', showStrengthBar: true)));
      await tester.enterText(find.byType(TextField), 'P@ssw0rdLong!');
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaPasswordField(label: 'Password', showStrengthBar: true),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(320, 120)),
        surfaceSize: const Size(320, 120),
      );
      await screenMatchesGolden(tester, 'sa_password_field_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaPasswordField(label: 'Password', showStrengthBar: true),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(320, 120)),
        surfaceSize: const Size(320, 120),
      );
      await screenMatchesGolden(tester, 'sa_password_field_dark');
    });
  });
}
