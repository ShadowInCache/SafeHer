import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/theme/app_colors.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/core/theme/theme_extensions.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

void main() {
  group('AppTheme', () {
    testWidgets('renders in light mode without exception', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
    // Mirrors main.dart's shell so screens render over the same ambient
    // field users see; the scaffold background is transparent by design.
    builder: (context, child) =>
        SaAmbientBackground(child: child ?? const SizedBox.shrink()),
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              final saColors = context.saColors;
              // Surfaces are translucent so the ambient aurora tints them;
              // the underlying hue is still the light-mode base.
              expect(saColors.surfaceBase.a, lessThan(1.0));
              expect(saColors.surfaceBase.r, closeTo(1.0, 0.02));
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
    // Mirrors main.dart's shell so screens render over the same ambient
    // field users see; the scaffold background is transparent by design.
    builder: (context, child) =>
        SaAmbientBackground(child: child ?? const SizedBox.shrink()),
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              final saColors = context.saColors;
              // Translucent for the same reason as light mode, over the
              // dark-mode base hue.
              expect(saColors.surfaceBase.a, lessThan(1.0));
              expect(
                saColors.surfaceBase.toARGB32() & 0x00FFFFFF,
                AppColors.dark900.toARGB32() & 0x00FFFFFF,
              );
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
