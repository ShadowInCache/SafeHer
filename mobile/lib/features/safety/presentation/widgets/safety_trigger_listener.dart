import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/sensors/shake_detector.dart';
import '../../data/safety_providers.dart';

/// Runs the opt-in shake trigger for as long as it's switched on.
///
/// Wraps the app shell so the gesture works from any screen. It starts and
/// stops purely from the user's saved preference — there is no path where the
/// accelerometer is read without the switch being on.
///
/// Firing opens the SOS countdown; it never dispatches an alert directly.
/// The countdown is the confirmation step, and it is the same countdown a
/// manual SOS gets.
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
    final router = GoRouter.of(context);
    // Already in the emergency flow — a further shake shouldn't restack it.
    final current = router.routerDelegate.currentConfiguration.uri.path;
    if (current == '/emergency') return;
    router.go('/emergency?auto=1');
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
    return widget.child;
  }
}
