import 'package:flutter/animation.dart';

/// Motion tokens. See design system spec §ANIMATION TOKENS.
abstract final class AnimationTokens {
  static const Duration instant = Duration.zero;
  static const Duration micro = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 250);
  static const Duration comfortable = Duration(milliseconds: 350);
  static const Duration expressive = Duration(milliseconds: 500);
  static const Duration dramatic = Duration(milliseconds: 800);

  /// Looping ambient breathing/glow cycle (e.g. SOS FAB, ambient rings).
  static const Duration ambient = Duration(seconds: 3);

  static const Curve microCurve = Curves.easeOut;
  static const Curve fastCurve = Curves.easeInOut;
  static const Curve standardCurve = Curves.easeInOut;
  static const Curve comfortableCurve = Curves.easeInOutCubic;
  static const Curve dramaticCurve = Curves.elasticOut;

  /// Curve approximation of [expressiveSpring] for implicit animations
  /// (AnimatedContainer, flutter_animate, etc.) that accept a [Curve] but
  /// not a physics simulation.
  static const Curve expressiveCurve = Curves.easeOutBack;

  /// Physics-based spring matching SpringDescription(mass: 0.8, stiffness:
  /// 100, damping: derived critical-ish) for use with AnimationController +
  /// SpringSimulation where true spring physics are required (press/release
  /// bounce on buttons and cards).
  static const SpringDescription expressiveSpring = SpringDescription(
    mass: 0.8,
    stiffness: 100,
    damping: 12,
  );

  const AnimationTokens._();
}
