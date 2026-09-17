import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/background/safety_watch.dart';
import '../../../../core/sensors/shake_detector.dart';
import '../../data/glove_auto_trigger.dart';
import '../../data/safety_providers.dart';
import '../../data/threat_pipeline.dart';

/// Runs the opt-in shake trigger, and turns the glove's alarm decisions into
/// the SOS countdown.
///
/// Wraps the app shell so the gesture works from any screen. It starts and
/// stops purely from the user's saved preference — there is no path where the
/// accelerometer is read without the switch being on.
///
/// Firing opens the SOS countdown; it never dispatches an alert directly.
/// The countdown is the confirmation step, and it is the same countdown a
/// manual SOS gets.
///
/// **What this deliberately no longer does.** The glove's vote used to happen
/// in this widget's `build()`. That made automatic detection quietly
/// conditional on the app being drawn: Flutter stops pumping frames when the
/// app is backgrounded, so `build()` stopped running and a pocketed phone
/// detected nothing. The vote now lives in [GloveAutoTrigger], driven by
/// provider state rather than by frames, and this widget's remaining job is
/// the part that genuinely needs a `BuildContext` — showing the countdown.
class SafetyTriggerListener extends ConsumerStatefulWidget {
  const SafetyTriggerListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SafetyTriggerListener> createState() => _SafetyTriggerListenerState();
}

class _SafetyTriggerListenerState extends ConsumerState<SafetyTriggerListener> {
  ShakeDetector? _detector;

  @override
  void dispose() {
    _detector?.stop();
    super.dispose();
  }

  void _onShake() {
    if (!mounted) return;
    _raiseAlarm();
  }

  /// Starts the same cancellable countdown a manual SOS gets.
  ///
  /// Deliberately the identical path: an automatic trigger must not be
  /// faster, quieter, or harder to stop than one the user asked for.
  void _raiseAlarm() {
    if (!mounted) return;
    final router = GoRouter.of(context);
    // Already in the emergency flow — a further trigger shouldn't restack it.
    final current = router.routerDelegate.currentConfiguration.uri.path;
    if (current == '/emergency') return;
    router.go('/emergency?auto=1');
  }

  /// Handles an alarm the glove decided on, wherever the app happens to be.
  ///
  /// The navigation happens first and unconditionally. The widget tree is
  /// alive whenever this callback runs — a backgrounded app is frozen from
  /// drawing, not torn down — so routing to the countdown now means it is
  /// already on screen by the time the activity comes forward, rather than
  /// racing the wake-up.
  void _onGloveAlarm(GloveAlarmRequest request) {
    _raiseAlarm();

    // In the foreground the user is already looking at the countdown.
    // Otherwise the screen has to be woken, or the chance to say "I'm fine"
    // runs out behind a dark display — which would make the automatic trigger
    // harder to stop than a manual one, the exact thing _raiseAlarm avoids.
    if (_isForeground) return;
    ref.read(safetyForegroundServiceProvider).bringToForeground();
  }

  /// True when the app is on screen.
  ///
  /// A null lifecycle state means the binding has not reported one yet, which
  /// happens on the very first frames; treating that as foreground keeps the
  /// wake-up for cases actually known to be backgrounded.
  bool get _isForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  void _sync(bool enabled, int sensitivityLevel) {
    if (!enabled) {
      _detector?.stop();
      _detector = null;
      return;
    }

    final sensitivity = ShakeSensitivity.fromLevel(sensitivityLevel);
    if (_detector == null) {
      _detector = ShakeDetector(onShake: _onShake, sensitivity: sensitivity)..start();
    } else {
      _detector!.updateSensitivity(sensitivity);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(safetyPreferencesNotifierProvider).valueOrNull;
    // Defaults to disabled: until the real preference loads, nothing listens.
    _sync(prefs?.shakeTriggerEnabled ?? false, prefs?.shakeSensitivity ?? 2);

    // The glove is the second automatic trigger, alongside the shake gesture.
    // `ref.listen` rather than `ref.watch`: the callback is driven by the
    // provider, so an alarm decided while the app is backgrounded still
    // arrives here even though this method is not running.
    ref.listen<GloveAlarmRequest?>(gloveAutoTriggerProvider, (previous, next) {
      if (next == null || identical(previous, next)) return;
      _onGloveAlarm(next);
    });

    // Keeps the foreground service running for as long as a glove is
    // connected. Watched here because this widget sits above the router and
    // so outlives every screen, which is the lifetime the service needs.
    ref.watch(gloveWatchServiceProvider);

    // Starts and stops the three-signal pipeline with the active journey.
    //
    // A `keepAlive` provider is still lazy — it does nothing at all until
    // something reads it — so without this line the microphone and the weapon
    // detector would be fully wired, fully tested and never once constructed.
    // Read here for the same reason as the line above: this widget outlives
    // every screen, and detection must not stop because she navigated away.
    ref.watch(threatPipelineProvider);

    return widget.child;
  }
}
