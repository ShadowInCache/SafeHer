import 'package:flutter/material.dart' show DateUtils;

import '../../../core/theme/app_colors.dart';
import '../../../shared/components/charts/sa_bar_chart.dart';
import '../../../shared/components/charts/sa_donut_chart.dart';
import '../../../shared/components/charts/sa_heat_grid.dart';
import '../../../shared/models/threat_level.dart';
import '../domain/dashboard_repository.dart';
import '../domain/models/dashboard_analytics.dart';
import '../domain/models/dashboard_summary.dart';

const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _weeklyScores = [0.22, 0.35, 0.18, 0.48, 0.65, 0.3, 0.15];

/// Daily incident counts for the mock 30-day window. Deliberately lumpy —
/// a smooth synthetic curve makes chart bugs (off-by-one buckets, reversed
/// ordering) invisible during development.
const _mockSparkline = <double>[
  0, 0, 1, 0, 0, 2, 1, 0, 0, 0, 3, 1, 0, 0, 1, //
  0, 0, 0, 2, 4, 1, 0, 0, 1, 0, 0, 2, 1, 0, 1,
];

class DashboardRepositoryMock implements DashboardRepository {
  @override
  Future<DashboardSummary> getDashboardSummary() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return DashboardSummary(
      weeklyThreatTrend: [
        for (var i = 0; i < _weekdayLabels.length; i++)
          SaBarChartDatum(label: _weekdayLabels[i], value: _weeklyScores[i], level: ThreatLevel.fromScore(_weeklyScores[i])),
      ],
      eventBreakdown: const [
        SaDonutSegment(label: 'Motion', value: 6, color: AppColors.violet500),
        SaDonutSegment(label: 'Audio', value: 4, color: AppColors.coral500),
        SaDonutSegment(label: 'Vision', value: 3, color: AppColors.warning500),
        SaDonutSegment(label: 'Manual SOS', value: 1, color: AppColors.danger500),
      ],
    );
  }

  @override
  Future<DashboardAnalytics> getDashboardAnalytics() async {
    await Future.delayed(const Duration(milliseconds: 300));
    final now = DateTime.now();
    final last14 = _mockSparkline.sublist(_mockSparkline.length - 14);

    return DashboardAnalytics(
      totalIncidents: _mockSparkline.fold<double>(0, (sum, v) => sum + v).toInt(),
      trendPct: 18.5,
      incidentSparkline: _mockSparkline,
      threatDays: [
        for (var i = 0; i < last14.length; i++)
          ThreatDay(
            date: DateUtils.dateOnly(now.subtract(Duration(days: last14.length - 1 - i))),
            total: last14[i].toInt(),
            counts: _mockCountsFor(last14[i].toInt()),
          ),
      ],
      // Clustered around Hyderabad, matching the SRS's example coordinates.
      heatCells: const [
        SaHeatCell(lat: 17.38, lng: 78.48, weight: 5),
        SaHeatCell(lat: 17.39, lng: 78.49, weight: 3),
        SaHeatCell(lat: 17.41, lng: 78.47, weight: 2),
        SaHeatCell(lat: 17.36, lng: 78.51, weight: 1),
      ],
      confidenceBreakdown: const [
        SaDonutSegment(label: 'high', value: 4, color: AppColors.threatElevated),
        SaDonutSegment(label: 'medium', value: 7, color: AppColors.warning500),
        SaDonutSegment(label: 'low', value: 9, color: AppColors.success500),
      ],
      recentIncidents: [
        RecentIncident(
          id: 'inc_mock_1',
          title: 'Emergency SOS',
          threatLevel: 'critical',
          createdAt: now.subtract(const Duration(hours: 3)),
        ),
        RecentIncident(
          id: 'inc_mock_2',
          title: 'Unusual motion detected',
          threatLevel: 'medium',
          createdAt: now.subtract(const Duration(days: 2)),
        ),
        RecentIncident(
          id: 'inc_mock_3',
          title: 'Raised voice detected',
          threatLevel: 'low',
          createdAt: now.subtract(const Duration(days: 5)),
        ),
      ],
      deviceHealth: [
        DeviceHealth(
          deviceId: 'dev_mock_glove',
          deviceName: 'Smart Glove',
          deviceType: 'glove',
          batteryLevel: 82,
          signalStrength: -54,
          isActive: true,
          lastSeen: now.subtract(const Duration(minutes: 2)),
        ),
        DeviceHealth(
          deviceId: 'dev_mock_glasses',
          deviceName: 'Smart Glasses',
          deviceType: 'glasses',
          batteryLevel: 17,
          signalStrength: -71,
          isActive: true,
          lastSeen: now.subtract(const Duration(hours: 6)),
        ),
      ],
      // Mirrors the backend: no battery time series is persisted, so the
      // mock must not pretend one exists either.
      batteryHistoryAvailable: false,
      safetyScore: const SafetyScore(score: 76, windowDays: 7, incidentFreeStreakDays: 3),
    );
  }

  /// Spreads a day's total across severities so the drill-down sheet and the
  /// bar colours have something to differ over during development.
  Map<String, int> _mockCountsFor(int total) => switch (total) {
    0 => const {},
    1 => const {'low': 1},
    2 => const {'low': 1, 'medium': 1},
    3 => const {'medium': 2, 'high': 1},
    _ => {'medium': total - 2, 'high': 1, 'critical': 1},
  };
}
