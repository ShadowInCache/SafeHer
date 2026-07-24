import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_colors.dart';
import 'package:safeher_app/shared/components/feedback/sa_status_dot.dart';

import '../../../test_utils/widget_test_helpers.dart';

void main() {
  group('SaStatusDot', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaStatusDot(color: AppColors.success500), brightness: Brightness.light));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaStatusDot(color: AppColors.success500)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('live mode does not throw across pumps', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaStatusDot(color: AppColors.success500, live: true)));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    });

    testGoldens('golden - light and dark', (tester) async {
      await tester.pumpWidgetBuilder(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SaStatusDot(color: AppColors.success500),
            SizedBox(width: 12),
            SaStatusDot(color: AppColors.danger500),
          ],
        ),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(80, 40)),
        surfaceSize: const Size(80, 40),
      );
      await screenMatchesGolden(tester, 'sa_status_dot_light');
    });
  });
}
