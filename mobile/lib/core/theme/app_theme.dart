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
    final sa = isDark ? SafeHerColors.darkResolved() : SafeHerColors.lightResolved();

    final colorScheme = isDark
        ? const ColorScheme.dark(
            // Material wants a light primary against a dark ground, with dark
            // ink on top of it -- which is also what the design asks for: the
            // interactive colour lifts on night, rather than darkening.
            primary: AppColors.violet400,
            onPrimary: AppColors.dark900,
            secondary: AppColors.coral400,
            onSecondary: AppColors.dark900,
            surface: AppColors.dark800,
            onSurface: AppColors.neutral100,
            error: AppColors.dangerOnDark,
            onError: AppColors.dark900,
          )
        : const ColorScheme.light(
            primary: AppColors.violet600,
            onPrimary: AppColors.neutral50,
            secondary: AppColors.coral500,
            onSecondary: AppColors.neutral50,
            surface: AppColors.light50,
            onSurface: AppColors.neutral900,
            error: AppColors.dangerOnLight,
            onError: AppColors.neutral50,
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
      // Transparent so `SaAmbientBackground` (mounted above the router in
      // main.dart) shows through every screen. That widget paints the ground,
      // so nothing here is left unpainted.
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: textTheme,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: onSurface,
      ),
      // A plain hairline. This was a violet-tinted rule at 12-14% alpha, which
      // read as a smudge rather than a line; separation is now the divider's
      // whole job, so it gets a real colour.
      dividerColor: sa.line,
      extensions: [sa],
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // Opaque, matching the rest of the surfaces. These were translucent so
        // the aurora could tint them; with the aurora gone that would only
        // sample the flat ground.
        fillColor: sa.surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: sa.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: sa.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          // SRS Frontend 3.3: focus goes 1dp -> 2dp, in the interactive colour.
          borderSide: BorderSide(color: sa.interactive, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: colorScheme.error, width: 1),
        ),
      ),
    );
  }

  const AppTheme._();
}
