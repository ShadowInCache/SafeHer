import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// Detects a deliberate, sustained shake of the phone.
///
/// This exists as a *fallback* trigger for when the Smart Glove isn't worn or
/// isn't connected — it is not a replacement for the glove's own motion
/// sensing, which is far richer (flex, impact, gyro) and runs on hardware
/// built for it.
///
/// The bar for firing is deliberately high, because a false SOS costs the
/// user real credibility with their contacts:
///
///   * a single jolt is ignored — [_requiredShakes] separate above-threshold
///     movements must land inside [_windowDuration];
///   * after firing, [_cooldown] must elapse before it can fire again, so one
///     shaking episode raises exactly one alert;
///   * gravity (~9.81 m/s²) is subtracted, so simply holding the phone still
///     never registers.
class ShakeDetector {
  ShakeDetector({
    required this.onShake,
    ShakeSensitivity sensitivity = ShakeSensitivity.medium,
    Stream<AccelerometerEvent>? accelerometerStream,
  }) : _sensitivity = sensitivity,
       _stream = accelerometerStream;

  final void Function() onShake;
  ShakeSensitivity _sensitivity;
  final Stream<AccelerometerEvent>? _stream;

  StreamSubscription<AccelerometerEvent>? _subscription;
  final List<DateTime> _recentShakes = [];
  DateTime? _lastFiredAt;

  static const _requiredShakes = 3;
  static const _windowDuration = Duration(milliseconds: 1500);
  static const _minGapBetweenShakes = Duration(milliseconds: 120);
  static const _cooldown = Duration(seconds: 10);
  static const _gravity = 9.80665;

  bool get isListening => _subscription != null;

  void updateSensitivity(ShakeSensitivity sensitivity) => _sensitivity = sensitivity;

  void start() {
    if (_subscription != null) return;
    final stream = _stream ?? accelerometerEventStream();
    _subscription = stream.listen(_onEvent);
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _recentShakes.clear();
  }

  void _onEvent(AccelerometerEvent event) {
    final magnitude = math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    final netAcceleration = (magnitude - _gravity).abs();
    if (netAcceleration < _sensitivity.thresholdMetresPerSecondSquared) return;

    final now = DateTime.now();

    if (_lastFiredAt != null && now.difference(_lastFiredAt!) < _cooldown) return;

    // Consecutive samples from one continuous jolt shouldn't each count.
    if (_recentShakes.isNotEmpty && now.difference(_recentShakes.last) < _minGapBetweenShakes) {
      return;
    }

    _recentShakes
      ..add(now)
      ..removeWhere((timestamp) => now.difference(timestamp) > _windowDuration);

    if (_recentShakes.length >= _requiredShakes) {
      _recentShakes.clear();
      _lastFiredAt = now;
      onShake();
    }
  }
}

enum ShakeSensitivity {
  /// Hardest to trigger — needs a hard, deliberate shake.
  low(1, 18.0),
  medium(2, 13.0),

  /// Easiest to trigger; still requires three distinct movements.
  high(3, 9.0);

  const ShakeSensitivity(this.level, this.thresholdMetresPerSecondSquared);

  final int level;
  final double thresholdMetresPerSecondSquared;

  static ShakeSensitivity fromLevel(int level) => switch (level) {
    1 => ShakeSensitivity.low,
    3 => ShakeSensitivity.high,
    _ => ShakeSensitivity.medium,
  };

  String get label => switch (this) {
    ShakeSensitivity.low => 'Low — hard shake',
    ShakeSensitivity.medium => 'Medium',
    ShakeSensitivity.high => 'High — light shake',
  };
}
