import '../../../../shared/components/charts/sa_motion_chart.dart';

/// One tick of the live monitoring stream. In the mock flavor this is
/// synthesized locally on a 100ms timer; the real (Phase 4) implementation
/// will map incoming WebSocket/MQTT frames onto the same shape so panels
/// don't need to change.
class MonitoringSnapshot {
  const MonitoringSnapshot({
    required this.threatScore,
    required this.waveform,
    required this.dbLevel,
    required this.detectedEmotion,
    required this.motionWindow,
    required this.eventPins,
    required this.glassesConnected,
  });

  final double threatScore;
  final List<double> waveform;
  final double dbLevel;
  final String detectedEmotion;
  final List<MotionSample> motionWindow;
  final List<MotionEventPin> eventPins;
  final bool glassesConnected;
}
