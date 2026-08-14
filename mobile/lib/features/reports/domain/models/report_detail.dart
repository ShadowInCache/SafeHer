import '../../../../shared/components/charts/sa_motion_chart.dart';
import '../../../../shared/models/threat_level.dart';
import 'evidence_item.dart';
import 'gps_breadcrumb.dart';
import 'timeline_event.dart';

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
    this.timeline = const [],
    this.evidence = const [],
    this.gpsBreadcrumbs = const [],
    this.chainOfCustodyHash,
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
  final List<TimelineEvent> timeline;
  final List<EvidenceItem> evidence;
  final List<GpsBreadcrumb> gpsBreadcrumbs;

  /// SHA-256 of the full incident record, null when the backend hasn't
  /// computed one yet (older reports, or the mock fixture data).
  final String? chainOfCustodyHash;
}
