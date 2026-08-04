import 'dart:math';

import '../../../shared/components/charts/sa_motion_chart.dart';
import '../../../shared/models/threat_level.dart';
import '../domain/models/report_detail.dart';
import '../domain/models/report_summary.dart';
import '../domain/reports_repository.dart';

const _reports = [
  ReportSummary(
    id: '1',
    date: 'Aug 2',
    type: 'Elevated motion detected',
    level: ThreatLevel.elevated,
    summarySnippet: 'Sudden acceleration spike near Elm Street.',
  ),
  ReportSummary(
    id: '2',
    date: 'Aug 1',
    type: 'Routine check-in',
    level: ThreatLevel.safe,
    summarySnippet: 'All monitored signals within normal range.',
  ),
  ReportSummary(
    id: '3',
    date: 'Jul 30',
    type: 'Loud noise detected',
    level: ThreatLevel.caution,
    summarySnippet: 'Brief audio spike while walking home.',
  ),
  ReportSummary(
    id: '4',
    date: 'Jul 26',
    type: 'Rapid heart rate + motion',
    level: ThreatLevel.danger,
    summarySnippet: 'Sensor fusion flagged a possible struggle.',
  ),
];

const _fullSummaries = {
  '1': 'Your smart ring recorded a sudden acceleration spike consistent with a fall or impact near '
      'Elm Street. The event lasted 4 seconds before motion returned to baseline. No audio or vision '
      'signals corroborated a threat, so this was logged as elevated rather than escalated.',
  '2': 'A routine automatic check-in. Motion, audio, and vision signals were all within normal range '
      'for the full monitoring window.',
  '3': 'A brief loud-noise spike was detected while walking home. Ambient decibel level rose from a '
      'baseline of ~35dB to a peak of 78dB for under 2 seconds, then returned to normal.',
  '4': 'Motion sensors detected rapid, irregular movement combined with an unusually elevated heart '
      'rate reading. Sensor fusion flagged this pattern as consistent with a possible physical '
      'struggle. An alert was sent to your emergency contacts.',
};

const _locations = {
  '1': 'Elm Street, near 5th Ave',
  '2': 'Home — 221B Baker Street',
  '3': 'Maple Avenue, Block 4',
  '4': 'Riverside Park, East Path',
};

class ReportsRepositoryMock implements ReportsRepository {
  @override
  Future<List<ReportSummary>> getReports() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _reports;
  }

  @override
  Future<ReportDetail> getReportDetail(String id) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final summary = _reports.firstWhere((r) => r.id == id, orElse: () => _reports.first);
    final random = Random(id.hashCode);

    return ReportDetail(
      id: summary.id,
      date: summary.date,
      time: '${6 + random.nextInt(14)}:${(random.nextInt(6) * 10).toString().padLeft(2, '0')}',
      type: summary.type,
      level: summary.level,
      fullSummary: _fullSummaries[id] ?? summary.summarySnippet,
      locationLabel: _locations[id] ?? 'Unknown location',
      waveform: List.generate(64, (i) => (0.1 + random.nextDouble() * 0.6).clamp(0.0, 1.0)),
      motionSamples: List.generate(
        40,
        (i) => MotionSample(
          x: sin(i / 6) + random.nextDouble() * 0.2,
          y: cos(i / 5) + random.nextDouble() * 0.2,
          z: sin(i / 8) * 0.5 + random.nextDouble() * 0.2,
        ),
      ),
      motionEvents: const [
        MotionEventPin(sampleIndex: 18, label: 'Peak event', timestamp: 'T+00:04'),
      ],
    );
  }
}
