import 'package:flutter/material.dart';

class AppTheme {
  // Brand Colors - Stunning Safety Theme
  static const Color primaryPurple = Color(0xFF8B5CF6); // Vibrant purple
  static const Color primaryBlue = Color(0xFF3B82F6); // Electric blue
  static const Color primaryCyan = Color(0xFF06B6D4); // Cyan
  static const Color accentPink = Color(0xFFEC4899); // Pink accent
  static const Color successGreen = Color(0xFF10B981); // Emerald green
  static const Color warningAmber = Color(0xFFFBBF24); // Amber
  static const Color dangerRed = Color(0xFFEF4444); // Red for alerts
  static const Color safetyGold = Color(0xFFF59E0B); // Gold

  // Gradient Colors
  static const List<Color> primaryGradient = [
    Color(0xFF6366F1), // Indigo
    Color(0xFF8B5CF6), // Purple
    Color(0xFFEC4899), // Pink
  ];

  static const List<Color> backgroundGradient = [
    Color(0xFF0F172A), // Deep navy
    Color(0xFF1E1B4B), // Deep purple
    Color(0xFF312E81), // Purple-blue
  ];

  static const List<Color> cardGradient = [
    Color(0xFF1E293B), // Slate-800
    Color(0xFF334155), // Slate-700
  ];

  // Text colors with better contrast
  static const Color textPrimary = Color(0xFFFAFAFA); // Almost white
  static const Color textSecondary = Color(0xFFCBD5E1); // Light gray
  static const Color textTertiary = Color(0xFF94A3B8); // Medium gray

  // Surface colors
  static const Color surfaceDark = Color(0xFF1E293B);
  static const Color surfaceLight = Color(0xFF334155);
  static const Color surfaceAccent = Color(0xFF475569);

  // Glow colors for effects
  static const Color glowPurple = Color(0x40A78BFA);
  static const Color glowBlue = Color(0x4060A5FA);
  static const Color glowCyan = Color(0x4022D3EE);
  static const Color glowPink = Color(0x40F472B6);

  // Backward compatibility aliases
  static const Color primaryColor = primaryPurple;
  static const Color accentColor = primaryPurple;
  static const Color secondaryColor = successGreen;
  static const Color successColor = successGreen;
  static const Color warningColor = warningAmber;
  static const Color dangerColor = dangerRed;
  static const Color infoColor = primaryBlue;
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkSurface = surfaceDark;
  static const Color darkCard = surfaceDark;

  // Light Theme
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: primaryPurple,
    colorScheme: const ColorScheme.light(
      primary: primaryPurple,
      secondary: successGreen,
      error: dangerRed,
      surface: Colors.white,
      surfaceContainerHighest: Color(0xFFF8FAFC),
    ),
    scaffoldBackgroundColor: const Color(0xFFF8FAFC),

    // Text Theme - Better readability (System fonts)
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
      bodyLarge: TextStyle(fontSize: 16, color: Colors.black87, height: 1.5),
      bodyMedium: TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
    ),

    // AppBar Theme
    appBarTheme: const AppBarTheme(
      backgroundColor: primaryPurple,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),

    // Elevated Button Theme
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryPurple,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        shadowColor: glowPurple,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),

    // Card Theme
    cardTheme: CardThemeData(
      elevation: 4,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
    ),

    // Input Decoration Theme
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryPurple, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: dangerRed),
      ),
    ),
  );

  // Dark Theme - Stunning Safety Design
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: primaryPurple,
    colorScheme: const ColorScheme.dark(
      primary: primaryPurple,
      secondary: successGreen,
      error: dangerRed,
      surface: surfaceDark,
      surfaceContainerHighest: Color(0xFF0F172A),
    ),
    scaffoldBackgroundColor: const Color(0xFF0F172A),

    // Text Theme - Optimized for dark background (System fonts)
    textTheme: TextTheme(
      displayLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: textPrimary,
        letterSpacing: -0.5,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.5),
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      headlineMedium: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        letterSpacing: -0.2,
      ),
      bodyLarge: const TextStyle(
        fontSize: 16,
        color: textSecondary,
        height: 1.6,
        letterSpacing: 0.15,
      ),
      bodyMedium: const TextStyle(
        fontSize: 14,
        color: textTertiary,
        height: 1.5,
        letterSpacing: 0.1,
      ),
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0F172A),
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: textPrimary,
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryPurple,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 8,
        shadowColor: glowPurple,
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    ),

    cardTheme: CardThemeData(
      elevation: 8,
      shadowColor: Colors.black45,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: surfaceDark,
    ),
  );
}
