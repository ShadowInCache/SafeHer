import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/inputs/sa_otp_field.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaOTPField', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(SaOTPField(onCompleted: (_) {}), brightness: Brightness.light));
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsNWidgets(6));
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(SaOTPField(onCompleted: (_) {})));
      expect(tester.takeException(), isNull);
    });

    testWidgets('auto-advances and fires onCompleted when all digits filled', (tester) async {
      String? completed;
      await tester.pumpWidget(wrapWithTheme(SaOTPField(onCompleted: (code) => completed = code)));
      final fields = find.byType(TextField);
      for (var i = 0; i < 6; i++) {
        await tester.enterText(fields.at(i), '$i');
        await tester.pump();
      }
      expect(completed, '012345');
    });

    testWidgets('pasting full code distributes across boxes', (tester) async {
      String? completed;
      await tester.pumpWidget(wrapWithTheme(SaOTPField(onCompleted: (code) => completed = code)));
      await tester.enterText(find.byType(TextField).first, '123456');
      await tester.pump();
      expect(completed, '123456');
    });

    testWidgets('error status clears fields after shake', (tester) async {
      final key = GlobalKey<SaOTPFieldState>();
      await tester.pumpWidget(
        wrapWithTheme(SaOTPField(key: key, onCompleted: (_) {})),
      );
      await tester.enterText(find.byType(TextField).first, '123456');
      await tester.pump();

      await tester.pumpWidget(
        wrapWithTheme(SaOTPField(key: key, onCompleted: (_) {}, status: SaOTPFieldStatus.error)),
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        SaOTPField(onCompleted: (_) {}),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(340, 100)),
        surfaceSize: const Size(340, 100),
      );
      await screenMatchesGolden(tester, 'sa_otp_field_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        SaOTPField(onCompleted: (_) {}),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(340, 100)),
        surfaceSize: const Size(340, 100),
      );
      await screenMatchesGolden(tester, 'sa_otp_field_dark');
    });
  });
}
