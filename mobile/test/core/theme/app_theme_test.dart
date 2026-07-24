import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/theme/app_colors.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/core/theme/theme_extensions.dart';

void main() {
  group('AppTheme', () {
    testWidgets('renders in light mode without exception', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              final saColors = context.saColors;
              expect(saColors.surfaceBase, AppColors.light50);
              return const Scaffold(body: Text('light'));
            },
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('light'), findsOneWidget);
    });

    testWidgets('renders in dark mode without exception', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              final saColors = context.saColors;
              expect(saColors.surfaceBase, AppColors.dark900);
              return const Scaffold(body: Text('dark'));
            },
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('dark'), findsOneWidget);
    });

    test('exposes distinct color schemes per brightness', () {
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
      expect(AppTheme.light.colorScheme.primary, isNot(AppTheme.dark.colorScheme.primary));
    });
  });
}
