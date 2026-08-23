import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_shadows.dart';

/// Brightness-aware brand tokens that don't map cleanly onto Material's
/// [ColorScheme]: grounds and hairlines, ink, the interactive colour, and the
/// threat-state scale.
///
/// **Why these exist even though [AppColors] has the same names.** A colour
/// used as foreground cannot clear 4.5:1 against both the day ground and the
/// night one -- there is no value in that intersection. [AppColors] therefore
/// holds one mid value per role, tuned to clear 3:1 on either ground, and this
/// extension holds the properly resolved pair. Screens should read from here
/// (`context.saColors.safe`) rather than from [AppColors] directly; the
/// remaining direct references get migrated screen by screen.
@immutable
class SafeHerColors extends ThemeExtension<SafeHerColors> {
  const SafeHerColors({
    required this.glassFill,
    required this.glassBorder,
    required this.surfaceBase,
    required this.surfaceElevated,
    required this.surfaceHighest,
    required this.line,
    required this.ink,
    required this.inkMuted,
    required this.interactive,
    required this.sos,
    required this.threatSafe,
    required this.threatSafeGlow,
    required this.threatCaution,
    required this.threatCautionGlow,
    required this.threatElevated,
    required this.threatElevatedGlow,
    required this.threatDanger,
    required this.threatDangerGlow,
    required this.shadowLevel1,
    required this.shadowLevel2,
    required this.shadowLevel3,
    required this.shadowLevel4,
    required this.shadowLevel5,
  });

  final Color glassFill;
  final Color glassBorder;
  final Color surfaceBase;
  final Color surfaceElevated;
  final Color surfaceHighest;

  /// The hairline that separates sections. In this direction a 1px rule and
  /// space do the work that a filled card used to do.
  final Color line;

  /// Body and heading ink on [surfaceBase].
  final Color ink;

  /// Secondary ink: labels, captions, anything supporting.
  final Color inkMuted;

  /// "You can tap this." Reserved for interactive affordances, and never used
  /// to convey state.
  final Color interactive;

  /// The SOS red, and nothing else. Resolved per ground because this is the
  /// one control that must never read as *less* urgent than it is: the shared
  /// [AppColors.coral500] is tuned for the day ground and drops to 3.5:1 on
  /// night, which is the wrong direction to compromise for an emergency
  /// button.
  final Color sos;

  final Color threatSafe;
  final Color threatSafeGlow;
  final Color threatCaution;
  final Color threatCautionGlow;
  final Color threatElevated;
  final Color threatElevatedGlow;
  final Color threatDanger;
  final Color threatDangerGlow;

  final List<BoxShadow> shadowLevel1;
  final List<BoxShadow> shadowLevel2;
  final List<BoxShadow> shadowLevel3;
  final List<BoxShadow> shadowLevel4;
  final List<BoxShadow> shadowLevel5;

  static const dark = SafeHerColors(
    glassFill: AppColors.glassFillDark,
    glassBorder: AppColors.glassBorderDark,
    // Opaque, where these used to be translucent. Translucency existed so the
    // aurora behind them would tint every card; with the aurora retired it
    // would only sample the flat ground, at the cost of a saved layer.
    surfaceBase: AppColors.dark900,
    surfaceElevated: AppColors.dark800,
    surfaceHighest: AppColors.dark700,
    line: AppColors.dark700,
    ink: AppColors.neutral100,
    inkMuted: AppColors.neutral400,
    interactive: AppColors.violet400,
    sos: AppColors.coral400,
    // Lifted off the shared mid values: on a near-black ground the semantic
    // colours have to come up to stay legible.
    threatSafe: Color(0xFF4FB183),
    threatSafeGlow: Color(0x334FB183),
    threatCaution: Color(0xFFD9A22E),
    threatCautionGlow: Color(0x33D9A22E),
    threatElevated: Color(0xFFE8823C),
    threatElevatedGlow: Color(0x33E8823C),
    threatDanger: AppColors.dangerOnDark,
    threatDangerGlow: Color(0x4DE4573F),
    shadowLevel1: [],
    shadowLevel2: [],
    shadowLevel3: [],
    shadowLevel4: [],
    shadowLevel5: [],
  );

  static const light = SafeHerColors(
    glassFill: AppColors.glassFillLight,
    glassBorder: AppColors.glassBorderLight,
    surfaceBase: AppColors.light50,
    surfaceElevated: Color(0xFFF1EFEA),
    surfaceHighest: AppColors.neutral50,
    line: AppColors.light100,
    ink: AppColors.neutral900,
    inkMuted: AppColors.neutral500,
    interactive: AppColors.violet600,
    sos: AppColors.coral500,
    // Pushed down for the same reason, in the other direction.
    threatSafe: Color(0xFF276B4E),
    threatSafeGlow: Color(0x33276B4E),
    threatCaution: Color(0xFF8C6210),
    threatCautionGlow: Color(0x338C6210),
    threatElevated: Color(0xFFB4551A),
    threatElevatedGlow: Color(0x33B4551A),
    threatDanger: AppColors.dangerOnLight,
    threatDangerGlow: Color(0x4DB9291D),
    shadowLevel1: [],
    shadowLevel2: [],
    shadowLevel3: [],
    shadowLevel4: [],
    shadowLevel5: [],
  );

  /// Shadow lists are computed (not const) because [AppShadows] derives
  /// its color per-brightness; call this once at theme construction.
  static SafeHerColors darkResolved() => dark.copyWith(
    shadowLevel1: AppShadows.level1(dark: true),
    shadowLevel2: AppShadows.level2(dark: true),
    shadowLevel3: AppShadows.level3(dark: true),
    shadowLevel4: AppShadows.level4(dark: true),
    shadowLevel5: AppShadows.level5(dark: true),
  );

  static SafeHerColors lightResolved() => light.copyWith(
    shadowLevel1: AppShadows.level1(dark: false),
    shadowLevel2: AppShadows.level2(dark: false),
    shadowLevel3: AppShadows.level3(dark: false),
    shadowLevel4: AppShadows.level4(dark: false),
    shadowLevel5: AppShadows.level5(dark: false),
  );

  @override
  SafeHerColors copyWith({
    Color? glassFill,
    Color? glassBorder,
    Color? surfaceBase,
    Color? surfaceElevated,
    Color? surfaceHighest,
    Color? line,
    Color? ink,
    Color? inkMuted,
    Color? interactive,
    Color? sos,
    Color? threatSafe,
    Color? threatSafeGlow,
    Color? threatCaution,
    Color? threatCautionGlow,
    Color? threatElevated,
    Color? threatElevatedGlow,
    Color? threatDanger,
    Color? threatDangerGlow,
    List<BoxShadow>? shadowLevel1,
    List<BoxShadow>? shadowLevel2,
    List<BoxShadow>? shadowLevel3,
    List<BoxShadow>? shadowLevel4,
    List<BoxShadow>? shadowLevel5,
  }) {
    return SafeHerColors(
      glassFill: glassFill ?? this.glassFill,
      glassBorder: glassBorder ?? this.glassBorder,
      surfaceBase: surfaceBase ?? this.surfaceBase,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceHighest: surfaceHighest ?? this.surfaceHighest,
      line: line ?? this.line,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      interactive: interactive ?? this.interactive,
      sos: sos ?? this.sos,
      threatSafe: threatSafe ?? this.threatSafe,
      threatSafeGlow: threatSafeGlow ?? this.threatSafeGlow,
      threatCaution: threatCaution ?? this.threatCaution,
      threatCautionGlow: threatCautionGlow ?? this.threatCautionGlow,
      threatElevated: threatElevated ?? this.threatElevated,
      threatElevatedGlow: threatElevatedGlow ?? this.threatElevatedGlow,
      threatDanger: threatDanger ?? this.threatDanger,
      threatDangerGlow: threatDangerGlow ?? this.threatDangerGlow,
      shadowLevel1: shadowLevel1 ?? this.shadowLevel1,
      shadowLevel2: shadowLevel2 ?? this.shadowLevel2,
      shadowLevel3: shadowLevel3 ?? this.shadowLevel3,
      shadowLevel4: shadowLevel4 ?? this.shadowLevel4,
      shadowLevel5: shadowLevel5 ?? this.shadowLevel5,
    );
  }

  @override
  SafeHerColors lerp(ThemeExtension<SafeHerColors>? other, double t) {
    if (other is! SafeHerColors) return this;
    return SafeHerColors(
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      surfaceBase: Color.lerp(surfaceBase, other.surfaceBase, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceHighest: Color.lerp(surfaceHighest, other.surfaceHighest, t)!,
      line: Color.lerp(line, other.line, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      interactive: Color.lerp(interactive, other.interactive, t)!,
      sos: Color.lerp(sos, other.sos, t)!,
      threatSafe: Color.lerp(threatSafe, other.threatSafe, t)!,
      threatSafeGlow: Color.lerp(threatSafeGlow, other.threatSafeGlow, t)!,
      threatCaution: Color.lerp(threatCaution, other.threatCaution, t)!,
      threatCautionGlow: Color.lerp(threatCautionGlow, other.threatCautionGlow, t)!,
      threatElevated: Color.lerp(threatElevated, other.threatElevated, t)!,
      threatElevatedGlow: Color.lerp(threatElevatedGlow, other.threatElevatedGlow, t)!,
      threatDanger: Color.lerp(threatDanger, other.threatDanger, t)!,
      threatDangerGlow: Color.lerp(threatDangerGlow, other.threatDangerGlow, t)!,
      shadowLevel1: t < 0.5 ? shadowLevel1 : other.shadowLevel1,
      shadowLevel2: t < 0.5 ? shadowLevel2 : other.shadowLevel2,
      shadowLevel3: t < 0.5 ? shadowLevel3 : other.shadowLevel3,
      shadowLevel4: t < 0.5 ? shadowLevel4 : other.shadowLevel4,
      shadowLevel5: t < 0.5 ? shadowLevel5 : other.shadowLevel5,
    );
  }
}

extension SafeHerThemeContext on BuildContext {
  /// Shorthand for `Theme.of(context).extension<SafeHerColors>()!`.
  SafeHerColors get saColors => Theme.of(this).extension<SafeHerColors>()!;
}
