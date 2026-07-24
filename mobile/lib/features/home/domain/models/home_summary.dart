import '../../../../shared/components/cards/sa_stat_card.dart';
import '../../../../shared/models/threat_level.dart';

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

class DeviceSummary {
  const DeviceSummary({
    required this.id,
    required this.name,
    required this.batteryPercent,
    required this.signalStrength,
    required this.isOnline,
  });

  final String id;
  final String name;
  final double batteryPercent;
  final int signalStrength;
  final bool isOnline;
}

class AlertSummary {
  const AlertSummary({
    required this.id,
    required this.title,
    required this.timestamp,
    required this.level,
    required this.summary,
  });

  final String id;
  final String title;
  final String timestamp;
  final ThreatLevel level;
  final String summary;
}

class SafetyScoreSummary {
  const SafetyScoreSummary({required this.score, required this.streakDays, required this.trend});

  /// 0–100
  final int score;
  final int streakDays;
  final SaTrendDirection trend;
}

class HomeSummary {
  const HomeSummary({
    required this.userName,
    required this.hasUnreadAlerts,
    required this.threat,
    required this.devices,
    required this.waveformPreview,
    required this.motionPreview,
    required this.recentAlerts,
    required this.safetyScore,
  });

  final String userName;
  final bool hasUnreadAlerts;
  final ThreatSnapshot threat;
  final List<DeviceSummary> devices;
  final List<double> waveformPreview;
  final List<double> motionPreview;
  final List<AlertSummary> recentAlerts;
  final SafetyScoreSummary safetyScore;
}
