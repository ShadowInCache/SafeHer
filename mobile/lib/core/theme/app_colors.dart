import 'package:flutter/painting.dart';

/// SafeHer brand color tokens. See design system spec Â§COLOUR TOKENS.
abstract final class AppColors {
  // Primary â€” Deep Violet Scale
  static const violet50 = Color(0xFFF5F3FF);
  static const violet100 = Color(0xFFEDE9FE);
  static const violet200 = Color(0xFFDDD6FE);
  static const violet400 = Color(0xFFA78BFA);
  static const violet500 = Color(0xFF8B5CF6);
  static const violet600 = Color(0xFF7C3AED);
  static const violet700 = Color(0xFF6D28D9);
  static const violet800 = Color(0xFF5B21B6);
  static const violet900 = Color(0xFF4C1D95);
  static const violet950 = Color(0xFF2E1065);

  // Onboarding page-2 background accent (Tailwind indigo-900); not part of
  // the primary brand scale, used only for the Onboarding gradient per spec.
  static const indigo900 = Color(0xFF312E81);

  // Accent â€” Soft Coral Scale
  static const coral400 = Color(0xFFFF8A80);
  static const coral500 = Color(0xFFFF6B6B);
  static const coral600 = Color(0xFFE53935);
  static const coral700 = Color(0xFFC62828);

  /// Onboarding page-3 background accent (deep coral), used only for the
  /// Onboarding gradient per spec â€” not part of the interactive coral scale.
  static const coral900 = Color(0xFF7F1D1D);

  // Semantic
  static const success500 = Color(0xFF10B981);
  static const success900 = Color(0xFF064E3B);
  static const warning500 = Color(0xFFF59E0B);
  static const warning900 = Color(0xFF78350F);
  static const danger500 = Color(0xFFEF4444);
  static const info500 = Color(0xFF3B82F6);

  // Backgrounds
  static const dark900 = Color(0xFF0A0A0F);
  static const dark800 = Color(0xFF12121A);
  static const dark700 = Color(0xFF1C1C28);
  static const dark600 = Color(0xFF252535);
  static const light50 = Color(0xFFF9FAFB);
  static const light100 = Color(0xFFF3F4F6);

  // Threat state system
  static const threatSafe = Color(0xFF10B981);
  static const threatSafeGlow = Color(0x3310B981); // 0.20 alpha
  static const threatCaution = Color(0xFFF59E0B);
  static const threatCautionGlow = Color(0x33F59E0B); // 0.20 alpha
  static const threatElevated = Color(0xFFF97316);
  static const threatElevatedGlow = Color(0x33F97316); // 0.20 alpha
  static const threatDanger = Color(0xFFEF4444);
  static const threatDangerGlow = Color(0x4DEF4444); // 0.30 alpha

  // Glassmorphism
  static const glassFillDark = Color(0x0FFFFFFF); // white 6%
  static const glassBorderDark = Color(0x1AFFFFFF); // white 10%
  static const glassFillLight = Color(0xB3FFFFFF); // white 70%
  static const glassBorderLight = Color(0xE6FFFFFF); // white 90%

  // ---------------------------------------------------------------------
  // Ambient (decorative only)
  //
  // The aurora field painted behind every screen by `SaAmbientBackground`.
  // These are the SRS's "warm violet glows" (Frontend section 1) rendered as
  // an actual light source rather than a flat fill.
  //
  // Deliberately NOT part of the semantic or interactive palette: nothing is
  // ever tinted with these to convey state. `auroraRose` in particular is a
  // pink, chosen because it reads warm and feminine-forward without colliding
  // with `coral500` -- coral means SOS and danger, and a decorative wash in the
  // same hue would blunt that signal.
  static const auroraViolet = Color(0xFF7C3AED);
  static const auroraRose = Color(0xFFF472B6);
  static const auroraDeep = Color(0xFF2E1065);

  // Neutral text helpers (dark mode primary surface content)
  static const neutral50 = Color(0xFFFAFAFA);
  static const neutral100 = Color(0xFFF4F4F5);
  static const neutral300 = Color(0xFFD4D4D8);
  static const neutral400 = Color(0xFFA1A1AA);
  static const neutral500 = Color(0xFF71717A);
  static const neutral700 = Color(0xFF3F3F46);
  static const neutral900 = Color(0xFF18181B);

  const AppColors._();
}
