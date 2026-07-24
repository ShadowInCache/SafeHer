import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

/// Type scale. See design system spec §TYPOGRAPHY.
///
/// Primary font: Inter. Data font: JetBrains Mono. Colors are intentionally
/// omitted here — [AppTheme] applies the correct on-surface color per
/// brightness via [TextStyle.copyWith].
abstract final class AppTypography {
  static TextStyle get displayXL =>
      GoogleFonts.inter(fontSize: 48, fontWeight: FontWeight.w800, height: 1.1);

  static TextStyle get displayL =>
      GoogleFonts.inter(fontSize: 36, fontWeight: FontWeight.w700, height: 1.15);

  static TextStyle get displayM =>
      GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w700, height: 1.2);

  static TextStyle get headingL =>
      GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w600, height: 1.3);

  static TextStyle get headingM =>
      GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, height: 1.35);

  static TextStyle get headingS =>
      GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4);

  static TextStyle get bodyL =>
      GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400, height: 1.6);

  static TextStyle get bodyM =>
      GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, height: 1.6);

  static TextStyle get bodyS =>
      GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, height: 1.5);

  static TextStyle get labelL =>
      GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, height: 1.2);

  static TextStyle get labelM =>
      GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, height: 1.2);

  static TextStyle get monoDataL =>
      GoogleFonts.jetBrainsMono(fontSize: 28, fontWeight: FontWeight.w700, height: 1.0);

  static TextStyle get monoDataM =>
      GoogleFonts.jetBrainsMono(fontSize: 20, fontWeight: FontWeight.w600, height: 1.1);

  static TextStyle get monoDataS =>
      GoogleFonts.jetBrainsMono(fontSize: 14, fontWeight: FontWeight.w500, height: 1.2);

  const AppTypography._();
}
