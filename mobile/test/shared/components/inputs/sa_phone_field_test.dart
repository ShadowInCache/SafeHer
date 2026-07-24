import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/inputs/sa_phone_field.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('toE164', () {
    test('formats country code and national number', () {
      expect(toE164('+1', '(555) 123-4567'), '+15551234567');
    });

    test('strips leading plus from country code before rejoining', () {
      expect(toE164('91', '9876543210'), '+919876543210');
    });
  });

  group('SaPhoneField', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaPhoneField(countryCode: '+1'), brightness: Brightness.light));
      expect(tester.takeException(), isNull);
      expect(find.text('+1'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaPhoneField(countryCode: '+1')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles tap on country code', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrapWithTheme(SaPhoneField(countryCode: '+1', onCountryCodeTap: () => tapped = true)),
      );
      await tester.tap(find.text('+1'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaPhoneField(countryCode: '+1'),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(320, 100)),
        surfaceSize: const Size(320, 100),
      );
      await screenMatchesGolden(tester, 'sa_phone_field_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaPhoneField(countryCode: '+1'),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(320, 100)),
        surfaceSize: const Size(320, 100),
      );
      await screenMatchesGolden(tester, 'sa_phone_field_dark');
    });
  });
}
