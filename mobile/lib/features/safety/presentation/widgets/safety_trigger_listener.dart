import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/sensors/shake_detector.dart';
import '../../../devices/domain/glove_threat_detector.dart';
import '../../../devices/domain/glove_protocol.dart';
import '../../../devices/data/glove_link_providers.dart';
import '../../../../core/local/app_preferences.dart';
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

  /// Votes on the glove's classifications. Held here rather than in the
  /// provider so its window and cooldown survive rebuilds, and so the
  /// decision logic stays a plain object that can be argued with in a test.
  final _gloveDetector = GloveThreatDetector();
  GloveClassification? _lastSeen;

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

  /// Feeds a new glove classification to the detector.
  ///
  /// Only genuinely new readings are fed: the provider rebuilds this widget
  /// for telemetry ticks too, and counting the same `FALL` twice because the
  /// battery percentage changed would halve the evidence an alarm needs.
  void _onGloveClassification(GloveClassification? classification, double threshold) {
    if (classification == null) return;
    if (identical(classification, _lastSeen)) return;
    _lastSeen = classification;

    final fire = _gloveDetector.shouldTrigger(
      classification,
      threshold: threshold,
      now: DateTime.now(),
    );
    if (fire) _raiseAlarm();
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
    // Its sensitivity is the same threat threshold the Profile screen exposes
    // (SRS FR-EMG-02), so one control governs how eager automatic detection
    // is rather than each source inventing its own.
    final link = ref.watch(gloveLinkProvider);
    final threshold = ref.watch(appPreferencesProvider).threatThreshold;
    if (!link.isListening) {
      // A disconnected glove clears the vote: readings from before a dropout
      // must not combine with ones after it.
      _gloveDetector.reset();
      _lastSeen = null;
    } else {
      _onGloveClassification(link.classification, threshold);
    }

    return widget.child;
  }
}
