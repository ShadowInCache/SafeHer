import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_typography.dart';
import 'theme_extensions.dart';

/// Builds the app's light and dark [ThemeData]. Screens/components should
/// pull colors from `Theme.of(context).colorScheme` and `context.saColors`
/// rather than referencing [AppColors] directly, so both modes stay correct.
abstract final class AppTheme {
  static ThemeData get dark => _build(brightness: Brightness.dark);

  static ThemeData get light => _build(brightness: Brightness.light);

  static ThemeData _build({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = isDark
        ? const ColorScheme.dark(
            primary: AppColors.violet500,
            onPrimary: Colors.white,
            secondary: AppColors.coral500,
            onSecondary: Colors.white,
            surface: AppColors.dark800,
            onSurface: AppColors.neutral100,
            error: AppColors.danger500,
            onError: Colors.white,
          )
        : const ColorScheme.light(
            primary: AppColors.violet600,
            onPrimary: Colors.white,
            secondary: AppColors.coral500,
            onSecondary: Colors.white,
            surface: AppColors.light50,
            onSurface: AppColors.neutral900,
            error: AppColors.danger500,
            onError: Colors.white,
          );

    final onSurface = colorScheme.onSurface;
    final onSurfaceMuted = isDark ? AppColors.neutral400 : AppColors.neutral500;

    final textTheme = TextTheme(
      displayLarge: AppTypography.displayXL.copyWith(color: onSurface),
      displayMedium: AppTypography.displayL.copyWith(color: onSurface),
      displaySmall: AppTypography.displayM.copyWith(color: onSurface),
      headlineLarge: AppTypography.headingL.copyWith(color: onSurface),
      headlineMedium: AppTypography.headingM.copyWith(color: onSurface),
      headlineSmall: AppTypography.headingS.copyWith(color: onSurface),
      bodyLarge: AppTypography.bodyL.copyWith(color: onSurface),
      bodyMedium: AppTypography.bodyM.copyWith(color: onSurfaceMuted),
      bodySmall: AppTypography.bodyS.copyWith(color: onSurfaceMuted),
      labelLarge: AppTypography.labelL.copyWith(color: onSurface),
      labelMedium: AppTypography.labelM.copyWith(color: onSurfaceMuted),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark ? AppColors.dark900 : AppColors.light50,
      textTheme: textTheme,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: onSurface,
      ),
      dividerColor: isDark ? AppColors.dark600 : AppColors.light100,
      extensions: [
        isDark ? SafeHerColors.darkResolved() : SafeHerColors.lightResolved(),
      ],
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.dark700 : Colors.white,
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: isDark ? AppColors.dark600 : AppColors.light100),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: isDark ? AppColors.dark600 : AppColors.light100),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: const BorderSide(color: AppColors.violet500, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: const BorderSide(color: AppColors.coral500, width: 1),
        ),
      ),
    );
  }

  const AppTheme._();
}
