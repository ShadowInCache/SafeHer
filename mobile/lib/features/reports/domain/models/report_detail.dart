import '../../../../shared/components/charts/sa_motion_chart.dart';
import '../../../../shared/models/threat_level.dart';

class ReportDetail {
  const ReportDetail({
    required this.id,
    required this.date,
    required this.time,
    required this.type,
    required this.level,
    required this.fullSummary,
    required this.locationLabel,
    required this.waveform,
    required this.motionSamples,
    required this.motionEvents,
  });

  final String id;
  final String date;
  final String time;
  final String type;
  final ThreatLevel level;
  final String fullSummary;
  final String locationLabel;
  final List<double> waveform;
  final List<MotionSample> motionSamples;
  final List<MotionEventPin> motionEvents;
}
