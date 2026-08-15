import 'dart:ui';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/components/charts/sa_bar_chart.dart';
import '../../../shared/components/charts/sa_donut_chart.dart';
import '../../../shared/components/charts/sa_heat_grid.dart';
import '../../../shared/models/threat_level.dart';
import '../domain/dashboard_repository.dart';
import '../domain/models/dashboard_analytics.dart';
import '../domain/models/dashboard_summary.dart';

/// `fastapi_app`-backed [DashboardRepository] — `/dashboard/summary` for the
/// Home strip and `/dashboard/analytics` for the Dashboard screen.
///
/// Every number here is a real aggregation over this user's own incidents
/// (see `fastapi_app/routers/dashboard.py`). Where the backend has nothing to
/// report it says so — a null trend, an empty heatmap,
/// `device_battery_history_available: false` — and this layer passes that
/// through untouched rather than substituting a plausible-looking zero.
class DashboardRepositoryRemote implements DashboardRepository {
  DashboardRepositoryRemote({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Color _colorForLevel(String level) => switch (level.toLowerCase()) {
    'critical' => AppColors.danger500,
    'high' => AppColors.threatElevated,
    'medium' => AppColors.warning500,
    'low' => AppColors.success500,
    _ => AppColors.neutral400,
  };

  ThreatLevel _barLevelForCount(int count) {
    if (count >= 3) return ThreatLevel.danger;
    if (count == 2) return ThreatLevel.elevated;
    if (count == 1) return ThreatLevel.caution;
    return ThreatLevel.safe;
  }

  String _shortDay(String isoDate) {
    final date = DateTime.tryParse(isoDate);
    if (date == null) return isoDate;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  @override
  Future<DashboardSummary> getDashboardSummary() async {
    final response = await _apiClient.dio.get('/dashboard/summary');
    final json = response.data as Map<String, dynamic>;

    final breakdown = (json['threat_level_breakdown'] as Map<String, dynamic>?) ?? const {};
    final last7Days = (json['incidents_last_7_days'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();

    return DashboardSummary(
      weeklyThreatTrend: [
        for (final day in last7Days)
          SaBarChartDatum(
            label: _shortDay(day['date'] as String),
            value: (day['count'] as num).toDouble(),
            level: _barLevelForCount(day['count'] as int),
          ),
      ],
      eventBreakdown: [
        for (final entry in breakdown.entries)
          SaDonutSegment(label: entry.key, value: (entry.value as num).toDouble(), color: _colorForLevel(entry.key)),
      ],
    );
  }

  @override
  Future<DashboardAnalytics> getDashboardAnalytics() async {
    final response = await _apiClient.dio.get('/dashboard/analytics');
    final json = response.data as Map<String, dynamic>;

    final threatByDay = (json['threat_by_day'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final sparkline = (json['incidents_last_30_days'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final heatmap = (json['heatmap'] as Map<String, dynamic>?) ?? const {};
    final breakdown = (json['confidence_breakdown'] as Map<String, dynamic>?) ?? const {};
    final score = (json['safety_score'] as Map<String, dynamic>?) ?? const {};

    return DashboardAnalytics(
      totalIncidents: (json['total_incidents'] as num?)?.toInt() ?? 0,
      trendPct: (json['trend_pct'] as num?)?.toDouble(),
      incidentSparkline: [
        for (final point in sparkline) (point['count'] as num).toDouble(),
      ],
      threatDays: [
        for (final day in threatByDay)
          ThreatDay(
            date: DateTime.parse(day['date'] as String),
            total: (day['total'] as num).toInt(),
            counts: {
              for (final entry in ((day['counts'] as Map<String, dynamic>?) ?? const {}).entries)
                entry.key: (entry.value as num).toInt(),
            },
          ),
      ],
      heatCells: [
        for (final cell in (heatmap['cells'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>())
          SaHeatCell(
            lat: (cell['lat'] as num).toDouble(),
            lng: (cell['lng'] as num).toDouble(),
            weight: (cell['weight'] as num).toInt(),
          ),
      ],
      confidenceBreakdown: [
        for (final entry in breakdown.entries)
          SaDonutSegment(
            label: entry.key,
            value: (entry.value as num).toDouble(),
            color: _colorForLevel(entry.key),
          ),
      ],
      recentIncidents: [
        for (final row in (json['recent_incidents'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>())
          RecentIncident(
            id: row['id'] as String,
            title: row['title'] as String,
            threatLevel: row['threat_level'] as String?,
            createdAt: DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
          ),
      ],
      deviceHealth: [
        for (final row in (json['device_health'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>())
          DeviceHealth(
            deviceId: row['device_id'] as String,
            deviceName: row['device_name'] as String,
            deviceType: row['device_type'] as String? ?? 'unknown',
            batteryLevel: (row['battery_level'] as num?)?.toInt(),
            signalStrength: (row['signal_strength'] as num?)?.toInt(),
            isActive: row['is_active'] as bool? ?? false,
            lastSeen: DateTime.tryParse(row['last_seen'] as String? ?? '')?.toLocal(),
          ),
      ],
      batteryHistoryAvailable: json['device_battery_history_available'] as bool? ?? false,
      safetyScore: SafetyScore(
        score: (score['score'] as num?)?.toInt() ?? 100,
        windowDays: (score['window_days'] as num?)?.toInt() ?? 7,
        incidentFreeStreakDays: (score['incident_free_streak_days'] as num?)?.toInt() ?? 0,
      ),
    );
  }

}
