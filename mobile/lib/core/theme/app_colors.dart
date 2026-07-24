import 'package:flutter/painting.dart';

/// SafeHer brand color tokens. See design system spec §COLOUR TOKENS.
abstract final class AppColors {
  // Primary — Deep Violet Scale
  static const violet50 = Color(0xFFF5F3FF);
  static const violet100 = Color(0xFFEDE9FE);
  static const violet500 = Color(0xFF8B5CF6);
  static const violet600 = Color(0xFF7C3AED);
  static const violet700 = Color(0xFF6D28D9);
  static const violet800 = Color(0xFF5B21B6);
  static const violet900 = Color(0xFF4C1D95);
  static const violet950 = Color(0xFF2E1065);

  // Accent — Soft Coral Scale
  static const coral400 = Color(0xFFFF8A80);
  static const coral500 = Color(0xFFFF6B6B);
  static const coral600 = Color(0xFFE53935);

  // Semantic
  static const success500 = Color(0xFF10B981);
  static const warning500 = Color(0xFFF59E0B);
  static const danger500 = Color(0xFFEF4444);

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
