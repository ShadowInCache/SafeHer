import '../../../../shared/components/cards/sa_stat_card.dart';

class ThreatSnapshot {
  const ThreatSnapshot({
    required this.score,
    required this.motionScore,
    required this.audioScore,
    required this.visionScore,
    required this.lastUpdated,
  });

  /// 0.0–1.0
  final double score;
  final double motionScore;
  final double audioScore;
  final double visionScore;
  final DateTime lastUpdated;
}

class SafetyScoreSummary {
  const SafetyScoreSummary({required this.score, required this.streakDays, required this.trend});

  /// 0–100
  final int score;
  final int streakDays;
  final SaTrendDirection trend;
}

/// Home-specific summary — live threat status, sensor preview data, and
/// the daily safety score. Identity (name), devices, and recent alerts are
/// NOT duplicated here; the screen reads those from their own shared
/// providers (profile, devices, reports) so they can never drift from what
/// those features' own screens show.
class HomeSummary {
  const HomeSummary({
    required this.hasUnreadAlerts,
    required this.threat,
    required this.waveformPreview,
    required this.motionPreview,
    required this.safetyScore,
  });

  final bool hasUnreadAlerts;
  final ThreatSnapshot threat;
  final List<double> waveformPreview;
  final List<double> motionPreview;
  final SafetyScoreSummary safetyScore;
}
