import '../../../../shared/models/threat_level.dart';

class ReportSummary {
  const ReportSummary({
    required this.id,
    required this.date,
    required this.type,
    required this.level,
    required this.summarySnippet,
  });

  final String id;
  final String date;
  final String type;
  final ThreatLevel level;
  final String summarySnippet;
}
