import 'package:flutter/painting.dart';

import 'app_colors.dart';

/// Elevation shadow tokens. See design system spec §ELEVATION / SHADOWS.
///
/// Elevation 0 = flat, 1 = list items, 2 = cards/inputs, 3 = floating/FAB,
/// 4 = sheets/dialogs, 5 = modals/SOS overlay.
abstract final class AppShadows {
  static const List<BoxShadow> none = [];

  static List<BoxShadow> level1({bool dark = true}) => [
    BoxShadow(
      color: dark ? const Color(0x1A7C3AED) : const Color(0x14000000),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> level2({bool dark = true}) => [
    BoxShadow(
      color: dark ? const Color(0x267C3AED) : const Color(0x1A000000),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> level3({bool dark = true}) => [
    BoxShadow(
      color: dark ? const Color(0x337C3AED) : const Color(0x1F000000),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> level4({bool dark = true}) => [
    BoxShadow(
      color: dark ? const Color(0x407C3AED) : const Color(0x26000000),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> level5({bool dark = true}) => [
    BoxShadow(
      color: dark ? const Color(0x4D7C3AED) : const Color(0x33000000),
      blurRadius: 40,
      offset: const Offset(0, 16),
    ),
  ];

  /// Convenience shadow used by the default SaCard elevation.
  static List<BoxShadow> medium({bool dark = true}) => level2(dark: dark);

  /// SOS glow used on the emergency button / danger states.
  static List<BoxShadow> sosGlow = const [
    BoxShadow(color: AppColors.threatDangerGlow, blurRadius: 32, spreadRadius: 4),
  ];

  const AppShadows._();
}
