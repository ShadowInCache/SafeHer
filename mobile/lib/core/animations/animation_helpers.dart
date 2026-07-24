import 'package:flutter/widgets.dart';

/// Reduced-motion-aware helpers. Every [AnimationController] driven
/// animation in the app MUST route through these instead of calling
/// `forward()`/`reverse()` directly, per the accessibility rules:
/// "Check MediaQuery.disableAnimations before every animation."
abstract final class AnimationHelpers {
  static bool reducedMotion(BuildContext context) =>
      MediaQuery.of(context).disableAnimations;

  /// Drives [controller] forward, or snaps instantly to the end state when
  /// the platform requests reduced motion.
  static TickerFuture forward(BuildContext context, AnimationController controller) {
    if (reducedMotion(context)) {
      controller.value = controller.upperBound;
      return TickerFuture.complete();
    }
    return controller.forward();
  }

  /// Drives [controller] backward, or snaps instantly to the start state
  /// when the platform requests reduced motion.
  static TickerFuture reverse(BuildContext context, AnimationController controller) {
    if (reducedMotion(context)) {
      controller.value = controller.lowerBound;
      return TickerFuture.complete();
    }
    return controller.reverse();
  }

  /// Repeats [controller] (for ambient/breathing loops), or leaves it
  /// static at rest when reduced motion is requested.
  static void repeat(BuildContext context, AnimationController controller, {bool reverse = false}) {
    if (reducedMotion(context)) {
      controller.value = controller.lowerBound;
      return;
    }
    controller.repeat(reverse: reverse);
  }

  /// Returns [duration] unchanged, or [Duration.zero] under reduced motion.
  /// Use for implicit animations (AnimatedContainer, AnimatedOpacity, ...).
  static Duration effectiveDuration(BuildContext context, Duration duration) {
    return reducedMotion(context) ? Duration.zero : duration;
  }

  const AnimationHelpers._();
}
