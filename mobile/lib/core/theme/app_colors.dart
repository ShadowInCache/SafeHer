import 'package:flutter/painting.dart';

/// SafeHer brand color tokens.
///
/// **Direction: "calm by default, unmistakable in emergency."** The previous
/// palette was blue-violet on near-black with coral used decoratively; the
/// file's own comment said "coral means SOS and danger" while coral tinted
/// quick actions and headings, so the escalation was spent before an emergency
/// could use it. This palette is warm stone and ink, with colour reserved for
/// meaning: green safe, ochre caution, oxide red danger, aubergine for what
/// you can tap. Everything else is a warm grey.
///
/// **Every token name here is unchanged**, and each ramp keeps its original
/// light-to-dark ordering, so the ~60 files that reference these directly
/// re-face themselves without being edited.
///
/// **Why the mid stops sit where they do.** Most of these are used as
/// *foreground* -- icon tints, chart segments, bold labels -- over either the
/// day ground or the night one. A colour cannot reach 4.5:1 against both
/// #E9E7E2 and #14130E; no value exists in that intersection. So the mid stops
/// are tuned to clear 3:1 on both grounds, which is the bar for icons, dots and
/// bold text, and [SafeHerColors] carries brightness-resolved values for the
/// places that need more.
abstract final class AppColors {
  // Primary -- Aubergine Scale (interactive: this is what "you can tap this"
  // looks like). Replaces the blue-violet ramp; same stops, same ordering.
  static const violet50 = Color(0xFFF5F2F8);
  static const violet100 = Color(0xFFEAE5F0);
  static const violet200 = Color(0xFFD6CDE3);
  static const violet400 = Color(0xFFA692D6); // night-leaning interactive
  static const violet500 = Color(0xFF7B69A8); // legible on both grounds
  static const violet600 = Color(0xFF5B4B85); // day-leaning interactive
  static const violet700 = Color(0xFF4A3D6E);
  static const violet800 = Color(0xFF3A3057);
  static const violet900 = Color(0xFF2B2440);
  static const violet950 = Color(0xFF1B1730);

  /// Onboarding page-2 background accent; not part of the interactive scale.
  static const indigo900 = Color(0xFF2E2A4A);

  // Accent -- Oxide Red Scale. This is SOS, and nothing else is.
  static const coral400 = Color(0xFFE4573F); // night-leaning
  static const coral500 = Color(0xFFC4362A); // the SOS red
  static const coral600 = Color(0xFFA82A20);
  static const coral700 = Color(0xFF8C2119);

  /// Onboarding page-3 background accent (deep oxide), gradient use only.
  static const coral900 = Color(0xFF4A1009);

  // Semantic. Mid stops clear 3:1 on both grounds -- see the class doc.
  static const success500 = Color(0xFF2E8B5F);
  static const success900 = Color(0xFF12402B);
  static const warning500 = Color(0xFF9C6B10);
  static const warning900 = Color(0xFF5A3D06);
  static const danger500 = Color(0xFFBF3124);
  static const info500 = Color(0xFF4A6DB5);

  /// Danger, resolved per ground. [danger500] is the both-grounds compromise
  /// and sits below 4.5:1 on night, which is fine for an icon and not fine for
  /// an error message. These two are the real values; they exist as constants
  /// rather than living only in [SafeHerColors] because `ColorScheme` entries
  /// have to be `const` and cannot read a theme extension.
  static const dangerOnDark = Color(0xFFE4573F);
  static const dangerOnLight = Color(0xFFB9291D);

  // Backgrounds. The `dark*` ramp is the night ground and its surfaces; the
  // `light*` pair is the day ground and its hairline.
  static const dark900 = Color(0xFF14130E); // night ground
  static const dark800 = Color(0xFF1D1B15); // night surface
  static const dark700 = Color(0xFF2C2A22); // night line
  static const dark600 = Color(0xFF3B382D); // night line, emphasised
  static const light50 = Color(0xFFE9E7E2); // day ground (warm stone)
  static const light100 = Color(0xFFD3CFC5); // day line

  // Threat state system. Mapped onto the semantic values above so a threat
  // level and a status colour can never drift apart.
  static const threatSafe = success500;
  static const threatSafeGlow = Color(0x332E8B5F); // 0.20 alpha
  static const threatCaution = warning500;
  static const threatCautionGlow = Color(0x339C6B10); // 0.20 alpha
  static const threatElevated = Color(0xFFC4621B);
  static const threatElevatedGlow = Color(0x33C4621B); // 0.20 alpha
  static const threatDanger = danger500;
  static const threatDangerGlow = Color(0x4DBF3124); // 0.30 alpha

  // ---------------------------------------------------------------------
  // Surfaces (formerly "glassmorphism")
  //
  // These were a translucent white fill and border, applied through a 16px
  // BackdropFilter to every surface in the app -- so a dark-mode toggle and an
  // SOS contact came out looking equally important, and nothing had hierarchy.
  //
  // They are now opaque surface and line tokens. The names are kept because
  // `SaCard` and friends still read them; retiring the blur itself is the next
  // pass, and until then it simply blurs whatever sits behind an opaque fill,
  // which is a no-op rather than a bug.
  static const glassFillDark = Color(0xFF1D1B15);
  static const glassBorderDark = Color(0xFF2C2A22);
  static const glassFillLight = Color(0xFFF1EFEA);
  static const glassBorderLight = Color(0xFFD3CFC5);

  // ---------------------------------------------------------------------
  // Ambient
  //
  // These were the aurora field's three glow hues. The field is gone -- the
  // new direction gets its depth from hairlines and space rather than from a
  // light source, and a violet wash behind warm stone would fight every token
  // above. `SaAmbientBackground` now paints the flat ground and these are the
  // colours it grounds to, one per brightness.
  static const auroraViolet = light50; // day ground
  static const auroraRose = light50;
  static const auroraDeep = dark900; // night ground

  // Neutral text helpers.
  static const neutral50 = Color(0xFFFAF8F4); // paper
  static const neutral100 = Color(0xFFEDE9E0); // night ink
  static const neutral300 = Color(0xFFC0BBAE);
  static const neutral400 = Color(0xFFA29C8D); // night ink, muted
  static const neutral500 = Color(0xFF6B675E); // day ink, muted
  static const neutral700 = Color(0xFF3A3730);
  static const neutral900 = Color(0xFF1B1A17); // day ink

  const AppColors._();
}
