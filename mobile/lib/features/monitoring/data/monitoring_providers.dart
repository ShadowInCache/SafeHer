import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/components/charts/sa_motion_chart.dart';
import '../domain/models/monitoring_snapshot.dart';

part 'monitoring_providers.g.dart';

const _emotions = ['calm', 'neutral', 'stressed'];

/// Synthesizes a live-updating [MonitoringSnapshot] on a 100ms tick — the
/// same shape a real WebSocket/MQTT-backed provider will produce in Phase
/// 4, so panels won't need to change when the mock is swapped out.
class _MonitoringStreamMock {
  final _random = Random();
  final _waveform = List<double>.filled(64, 0.1);
  final _motionWindow = <MotionSample>[];
  final _eventPins = <MotionEventPin>[];
  var _tick = 0;

  Stream<MonitoringSnapshot> stream() async* {
    final controller = StreamController<MonitoringSnapshot>();
    final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      controller.add(_nextSnapshot());
    });
    controller.onCancel = timer.cancel;
    yield* controller.stream;
  }

  MonitoringSnapshot _nextSnapshot() {
    _tick++;
    _waveform.removeAt(0);
    _waveform.add((0.15 + _random.nextDouble() * 0.35).clamp(0.0, 1.0));

    final sample = MotionSample(
      x: sin(_tick / 8) + _random.nextDouble() * 0.1,
      y: cos(_tick / 6) + _random.nextDouble() * 0.1,
      z: sin(_tick / 10) * 0.5 + _random.nextDouble() * 0.1,
    );
    _motionWindow.add(sample);
    if (_motionWindow.length > 60) _motionWindow.removeAt(0);

    if (_tick % 45 == 0) {
      _eventPins.add(MotionEventPin(
        sampleIndex: _motionWindow.length - 1,
        label: 'Motion spike',
        timestamp: _formatTimestamp(DateTime.now()),
      ));
      if (_eventPins.length > 5) _eventPins.removeAt(0);
    }

    final avgAmplitude = _waveform.reduce((a, b) => a + b) / _waveform.length;

    return MonitoringSnapshot(
      threatScore: (0.2 + avgAmplitude * 0.3).clamp(0.0, 1.0),
      waveform: List.unmodifiable(_waveform),
      dbLevel: 30 + avgAmplitude * 50,
      detectedEmotion: _emotions[(_tick ~/ 30) % _emotions.length],
      motionWindow: List.unmodifiable(_motionWindow),
      eventPins: List.unmodifiable(_eventPins),
      glassesConnected: false,
    );
  }
}

String _formatTimestamp(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';

@riverpod
Stream<MonitoringSnapshot> monitoringStream(Ref ref) {
  final mock = _MonitoringStreamMock();
  return mock.stream();
}
