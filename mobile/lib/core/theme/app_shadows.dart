import 'package:flutter/painting.dart';

import 'app_colors.dart';

/// Elevation shadow tokens. See SRS Frontend section 2.4.
///
/// Elevation 0 = flat, 1 = list items, 2 = cards/inputs, 3 = floating/FAB,
/// 4 = sheets/dialogs, 5 = modals/SOS overlay.
///
/// Every level is tinted with the brand violet in both brightnesses, which is
/// what the SRS specifies (it gives one violet value per level, not a
/// per-brightness pair). Light mode previously used neutral black, which is the
/// main reason it read as generic Material grey rather than as SafeHer: a violet
/// shadow tints the page around each card and carries the brand into the light
/// theme the same way the aurora does.
///
/// Light mode carries slightly more alpha than the raw spec value because
/// violet-on-white is far less visible than violet-on-near-black; matching the
/// numbers literally there would produce no perceptible depth at all.
abstract final class AppShadows {
  static const List<BoxShadow> none = [];

  static const _violet = AppColors.violet600;

  static List<BoxShadow> _shadow({
    required bool dark,
    required double darkAlpha,
    required double lightAlpha,
    required double blur,
    required double dy,
  }) => [
    BoxShadow(
      color: _violet.withValues(alpha: dark ? darkAlpha : lightAlpha),
      blurRadius: blur,
      offset: Offset(0, dy),
    ),
  ];

  static List<BoxShadow> level1({bool dark = true}) =>
      _shadow(dark: dark, darkAlpha: 0.10, lightAlpha: 0.08, blur: 3, dy: 1);

  static List<BoxShadow> level2({bool dark = true}) =>
      _shadow(dark: dark, darkAlpha: 0.15, lightAlpha: 0.12, blur: 12, dy: 4);

  static List<BoxShadow> level3({bool dark = true}) =>
      _shadow(dark: dark, darkAlpha: 0.20, lightAlpha: 0.18, blur: 24, dy: 8);

  static List<BoxShadow> level4({bool dark = true}) =>
      _shadow(dark: dark, darkAlpha: 0.30, lightAlpha: 0.24, blur: 40, dy: 16);

  static List<BoxShadow> level5({bool dark = true}) =>
      _shadow(dark: dark, darkAlpha: 0.40, lightAlpha: 0.30, blur: 60, dy: 24);

  /// Convenience shadow used by the default SaCard elevation.
  static List<BoxShadow> medium({bool dark = true}) => level2(dark: dark);

  /// SOS glow used on the emergency button / danger states.
  static List<BoxShadow> sosGlow = const [
    BoxShadow(color: AppColors.threatDangerGlow, blurRadius: 32, spreadRadius: 4),
  ];

  const AppShadows._();
}
