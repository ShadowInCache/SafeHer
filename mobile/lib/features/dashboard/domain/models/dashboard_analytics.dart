import 'package:flutter/foundation.dart';

import '../../../../shared/components/charts/sa_bar_chart.dart';
import '../../../../shared/components/charts/sa_donut_chart.dart';
import '../../../../shared/components/charts/sa_heat_grid.dart';
import '../../../../shared/models/threat_level.dart';

/// Everything the Dashboard screen (SRS Part 3, SCREEN 9) renders, aggregated
/// server-side by `GET /api/v1/dashboard/analytics`.
///
/// The nullable and "available" flags here are load-bearing, not defensive
/// noise: the backend distinguishes "no baseline to compare against" from
/// "no change", and "no battery history is stored" from "battery is flat".
/// Collapsing either distinction into a zero would put a fabricated number
/// on a safety dashboard.
@immutable
class DashboardAnalytics {
  const DashboardAnalytics({
    required this.totalIncidents,
    required this.trendPct,
    required this.incidentSparkline,
    required this.threatDays,
    required this.heatCells,
    required this.confidenceBreakdown,
    required this.recentIncidents,
    required this.deviceHealth,
    required this.batteryHistoryAvailable,
    required this.safetyScore,
  });

  /// Lifetime incident count for this user.
  final int totalIncidents;

  /// Percent change over the last 30 days against the 30 before it, or null
  /// when there is no prior window to compare against.
  final double? trendPct;

  /// Daily incident counts, oldest first, 30 entries.
  final List<double> incidentSparkline;

  /// Per-day threat breakdown for the last 14 days, oldest first.
  final List<ThreatDay> threatDays;

  /// [threatDays] shaped for [SaBarChart]. Derived rather than stored so the
  /// bars and the drill-down sheet can never disagree about a day.
  List<SaBarChartDatum> get threatBars => [
    for (final day in threatDays)
      SaBarChartDatum(label: '${day.date.day}', value: day.total.toDouble(), level: day.level),
  ];

  /// Incident locations aggregated into ~1.1 km cells. Empty when no
  /// incident carried a location.
  final List<SaHeatCell> heatCells;

  /// Distribution of incidents across threat levels.
  final List<SaDonutSegment> confidenceBreakdown;

  /// Up to three most recent incidents, newest first.
  final List<RecentIncident> recentIncidents;

  final List<DeviceHealth> deviceHealth;

  /// False while the backend stores only a current battery reading per
  /// device. The card renders live readings instead of a trend line.
  final bool batteryHistoryAvailable;

  final SafetyScore safetyScore;

  /// True when the account has nothing to show yet — drives the empty state
  /// rather than a page of zeroed-out charts.
  bool get isEmpty => totalIncidents == 0 && deviceHealth.isEmpty;
}

/// One day of the 14-day threat strip, and the payload behind tapping its
/// bar (SRS SCREEN 9, Card 2: "onBarTap(date) → incident list for that day").
@immutable
class ThreatDay {
  const ThreatDay({required this.date, required this.total, required this.counts});

  final DateTime date;
  final int total;

  /// Incident count keyed by threat level (`critical`/`high`/`medium`/`low`,
  /// plus `unknown` for incidents recorded without a label).
  final Map<String, int> counts;

  /// Severity of the worst incident that day — what the bar is coloured by.
  /// A day with one critical incident must not read as calmer than a day
  /// with three low ones, so this is a max, not an average.
  ThreatLevel get level {
    if ((counts['critical'] ?? 0) > 0) return ThreatLevel.danger;
    if ((counts['high'] ?? 0) > 0) return ThreatLevel.elevated;
    // Anything else that happened still happened: `safe` is reserved for a
    // day with no incidents at all.
    if (total > 0) return ThreatLevel.caution;
    return ThreatLevel.safe;
  }
}

@immutable
class RecentIncident {
  const RecentIncident({
    required this.id,
    required this.title,
    required this.threatLevel,
    required this.createdAt,
  });

  final String id;
  final String title;

  /// Null when the incident was recorded without a severity label.
  final String? threatLevel;
  final DateTime createdAt;
}

@immutable
class DeviceHealth {
  const DeviceHealth({
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.batteryLevel,
    required this.signalStrength,
    required this.isActive,
    required this.lastSeen,
  });

  final String deviceId;
  final String deviceName;
  final String deviceType;

  /// Null when the device has never reported a battery reading.
  final int? batteryLevel;
  final int? signalStrength;
  final bool isActive;
  final DateTime? lastSeen;
}

@immutable
class SafetyScore {
  const SafetyScore({
    required this.score,
    required this.windowDays,
    required this.incidentFreeStreakDays,
  });

  /// 0–100, computed by the backend as 100 minus a severity-weighted penalty
  /// for incidents inside [windowDays].
  final int score;
  final int windowDays;
  final int incidentFreeStreakDays;

  double get progress => (score / 100).clamp(0.0, 1.0);
}
