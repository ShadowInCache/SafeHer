import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

/// Type scale. See design system spec TYPOGRAPHY.
///
/// Primary font: Archivo. Data font: JetBrains Mono. Colors are intentionally
/// omitted here -- [AppTheme] applies the correct on-surface color per
/// brightness via [TextStyle.copyWith].
///
/// **Why Archivo and not Inter.** Inter is the default face of nearly every
/// generated app, so the interface had no voice before a word was read. Archivo
/// carries a real width axis as well as a weight axis, which is what makes
/// [displayCondensed] possible: the emergency screen can shout in the *same*
/// family rather than introducing a second one. Sizes and line heights below
/// are deliberately unchanged from the Inter ramp, so this swap re-faces every
/// screen without moving anything.
abstract final class AppTypography {
  static TextStyle get displayXL =>
      GoogleFonts.archivo(fontSize: 48, fontWeight: FontWeight.w800, height: 1.1);

  static TextStyle get displayL =>
      GoogleFonts.archivo(fontSize: 36, fontWeight: FontWeight.w700, height: 1.15);

  static TextStyle get displayM =>
      GoogleFonts.archivo(fontSize: 28, fontWeight: FontWeight.w700, height: 1.2);

  static TextStyle get headingL =>
      GoogleFonts.archivo(fontSize: 22, fontWeight: FontWeight.w600, height: 1.3);

  static TextStyle get headingM =>
      GoogleFonts.archivo(fontSize: 18, fontWeight: FontWeight.w600, height: 1.35);

  static TextStyle get headingS =>
      GoogleFonts.archivo(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4);

  static TextStyle get bodyL =>
      GoogleFonts.archivo(fontSize: 16, fontWeight: FontWeight.w400, height: 1.6);

  static TextStyle get bodyM =>
      GoogleFonts.archivo(fontSize: 14, fontWeight: FontWeight.w400, height: 1.6);

  static TextStyle get bodyS =>
      GoogleFonts.archivo(fontSize: 12, fontWeight: FontWeight.w400, height: 1.5);

  static TextStyle get labelL =>
      GoogleFonts.archivo(fontSize: 14, fontWeight: FontWeight.w500, height: 1.2);

  static TextStyle get labelM =>
      GoogleFonts.archivo(fontSize: 12, fontWeight: FontWeight.w500, height: 1.2);

  /// The alert register. Used only where a screen has escalated -- the
  /// dispatched emergency headline -- never for ordinary display copy.
  ///
  /// Sized against the screen it lives on rather than for maximum impact. At
  /// 56 it pushed "I'm Safe -- Cancel Alert" past the viewport's build range,
  /// which on a real phone means extra scrolling to call off a false alarm.
  /// A headline is not worth putting distance between a woman and the control
  /// that stops the thing she triggered by accident.
  static TextStyle get displayCondensed => GoogleFonts.archivoNarrow(
    fontSize: 42,
    fontWeight: FontWeight.w800,
    height: 0.95,
    letterSpacing: -0.5,
  );

  static TextStyle get monoDataL =>
      GoogleFonts.jetBrainsMono(fontSize: 28, fontWeight: FontWeight.w700, height: 1.0);

  static TextStyle get monoDataM =>
      GoogleFonts.jetBrainsMono(fontSize: 20, fontWeight: FontWeight.w600, height: 1.1);

  static TextStyle get monoDataS =>
      GoogleFonts.jetBrainsMono(fontSize: 14, fontWeight: FontWeight.w500, height: 1.2);

  const AppTypography._();
}
