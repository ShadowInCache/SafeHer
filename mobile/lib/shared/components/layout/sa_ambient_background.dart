import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// The aurora field painted behind every screen.
///
/// SRS Frontend section 1 asks for "warm violet glows", "layered depth" and
/// glassmorphism. Glass only reads as glass when there is something behind it
/// to refract; over a flat fill it collapses into a slightly lighter rectangle.
/// This widget is that something — overlapping radial gradients that give the
/// page a light source, so cards feel lit rather than drawn.
///
/// Two hues only. The SRS calls for restrained accent use, and the same brief
/// rules out cyberpunk neon-on-black, so the stops stay low-alpha: the effect
/// should read as depth, not as a light show.
///
/// Static by design. A drifting field would be prettier in isolation, but it
/// sits above the router and would therefore animate forever on every screen —
/// which never settles for `pumpAndSettle` and would make all ~200 golden tests
/// flaky. Motion belongs on the elements a user is actually looking at.
class SaAmbientBackground extends StatelessWidget {
  const SaAmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // `CustomPaint` with a child paints the painter *behind* that child and
    // passes its own constraints straight through. A Stack was wrong here: only
    // positioned children are excluded from sizing, so the app content became a
    // loosely-constrained child and shrink-wrapped instead of filling the
    // screen, which silently moved widgets out of hit-test range.
    // `CustomPaint` with a child paints the painter behind that child and passes
    // its own constraints straight through, so the app still fills the screen.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? AppColors.dark900 : AppColors.light50,
      ),
      child: CustomPaint(
        painter: _AuroraPainter(isDark: isDark),
        // The field is static, so it should not repaint when content above it
        // scrolls or animates.
        isComplex: true,
        willChange: false,
        child: child,
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  const _AuroraPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    // Alpha is the whole design here. In dark mode the field has to lift the
    // page off near-black without ever becoming a glow; in light mode it has to
    // tint an off-white page warm without muddying text contrast.
    final violetAlpha = isDark ? 0.30 : 0.20;
    final roseAlpha = isDark ? 0.16 : 0.14;
    final deepAlpha = isDark ? 0.55 : 0.0;

    // Offsets are fractions of the canvas so the composition holds from a
    // 360dp phone to a tablet.
    _glow(
      canvas,
      size,
      centre: Offset(size.width * 0.08, size.height * -0.04),
      radius: size.width * 1.15,
      colour: AppColors.auroraViolet.withValues(alpha: violetAlpha),
    );
    _glow(
      canvas,
      size,
      centre: Offset(size.width * 1.02, size.height * 0.22),
      radius: size.width * 0.95,
      colour: AppColors.auroraRose.withValues(alpha: roseAlpha),
    );
    // Anchors the lower half so the composition does not fade into a dead
    // rectangle below the fold — the flat-void problem this replaces.
    _glow(
      canvas,
      size,
      centre: Offset(size.width * 0.22, size.height * 1.05),
      radius: size.width * 1.30,
      colour: (isDark ? AppColors.auroraDeep : AppColors.auroraViolet).withValues(
        alpha: isDark ? deepAlpha : 0.10,
      ),
    );
    _glow(
      canvas,
      size,
      centre: Offset(size.width * 0.95, size.height * 0.92),
      radius: size.width * 0.80,
      colour: AppColors.auroraRose.withValues(alpha: isDark ? 0.10 : 0.09),
    );
  }

  void _glow(
    Canvas canvas,
    Size size, {
    required Offset centre,
    required double radius,
    required Color colour,
  }) {
    if (colour.a == 0) return;
    final paint = Paint()
      ..shader = RadialGradient(
        // A hard stop at the edge would draw a visible disc. Fading to fully
        // transparent well before the radius keeps the falloff organic.
        colors: [colour, colour.withValues(alpha: 0), colour.withValues(alpha: 0)],
        stops: const [0.0, 0.72, 1.0],
      ).createShader(Rect.fromCircle(center: centre, radius: radius));
    canvas.drawCircle(centre, radius, paint);
  }

  @override
  bool shouldRepaint(_AuroraPainter oldDelegate) => oldDelegate.isDark != isDark;
}
